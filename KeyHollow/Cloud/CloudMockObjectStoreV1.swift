import Foundation

enum CloudMockStoreErrorV1: Error, Equatable {
    case idempotencyConflict
    case invalidReservation
    case objectAlreadyExists
    case objectNotFound
    case objectNotCommitted
    case quotaExceeded
    case reservationSizeExceeded
    case staleParent
}

struct CloudMockReservationV1: Equatable, Sendable {
    let reservationID: UUID
    let accountID: UUID
    let vaultID: UUID
    let idempotencyKey: UUID
    let declaredByteCount: UInt64
}

struct CloudMockGenerationHeadV1: Equatable, Sendable {
    let accountID: UUID
    let vaultID: UUID
    let generation: UInt64
    let manifestObjectID: UUID
    let manifestSHA256: Data
    let objectIDs: Set<UUID>
}

struct CloudMockStoreStatisticsV1: Equatable, Sendable {
    let objectCount: Int
    let activeReservationCount: Int
    let retainedGenerationCount: Int
}

/// An in-memory provider/control-plane model for Gate A tests. It deliberately
/// stores only opaque identifiers, sizes, digests, and encrypted bytes.
actor CloudMockObjectStoreV1 {
    private struct ReservationRecord {
        let token: CloudMockReservationV1
        let createdAtMilliseconds: UInt64
        var uploadedByteCount: UInt64
        var objectIDs: Set<UUID>
        var finalizedHead: CloudMockGenerationHeadV1?
    }

    private struct ObjectRecord {
        let accountID: UUID
        let vaultID: UUID
        let reservationID: UUID
        let storedBytes: Data
        let sha256: Data
        let createdAtMilliseconds: UInt64
        var committed: Bool
    }

    private struct VaultIdentity: Hashable {
        let accountID: UUID
        let vaultID: UUID
    }

    private let quotaByteCount: UInt64
    private var reservations: [UUID: ReservationRecord] = [:]
    private var reservationByIdempotencyKey: [UUID: UUID] = [:]
    private var objects: [UUID: ObjectRecord] = [:]
    private var heads: [VaultIdentity: CloudMockGenerationHeadV1] = [:]
    private var generations: [VaultIdentity: [UInt64: CloudMockGenerationHeadV1]] = [:]

    init(quotaByteCount: UInt64) {
        self.quotaByteCount = quotaByteCount
    }

    func reserve(
        accountID: UUID,
        vaultID: UUID,
        idempotencyKey: UUID,
        declaredByteCount: UInt64,
        nowMilliseconds: UInt64
    ) throws -> CloudMockReservationV1 {
        guard declaredByteCount > 0 else {
            throw CloudMockStoreErrorV1.reservationSizeExceeded
        }
        if let existingID = reservationByIdempotencyKey[idempotencyKey],
           let existing = reservations[existingID] {
            guard existing.token.accountID == accountID,
                  existing.token.vaultID == vaultID,
                  existing.token.declaredByteCount == declaredByteCount else {
                throw CloudMockStoreErrorV1.idempotencyConflict
            }
            return existing.token
        }

        let used = retainedByteCount(accountID: accountID)
        let reserved = activeReservedByteCount(accountID: accountID)
        let (withReserved, firstOverflow) = used.addingReportingOverflow(reserved)
        let (total, secondOverflow) = withReserved.addingReportingOverflow(declaredByteCount)
        guard !firstOverflow, !secondOverflow, total <= quotaByteCount else {
            throw CloudMockStoreErrorV1.quotaExceeded
        }

        let token = CloudMockReservationV1(
            reservationID: UUID(),
            accountID: accountID,
            vaultID: vaultID,
            idempotencyKey: idempotencyKey,
            declaredByteCount: declaredByteCount
        )
        reservations[token.reservationID] = ReservationRecord(
            token: token,
            createdAtMilliseconds: nowMilliseconds,
            uploadedByteCount: 0,
            objectIDs: [],
            finalizedHead: nil
        )
        reservationByIdempotencyKey[idempotencyKey] = token.reservationID
        return token
    }

    func putObject(
        reservation: CloudMockReservationV1,
        objectID: UUID,
        storedBytes: Data,
        expectedSHA256: Data,
        nowMilliseconds: UInt64
    ) throws {
        guard var record = reservations[reservation.reservationID],
              record.token == reservation,
              record.finalizedHead == nil else {
            throw CloudMockStoreErrorV1.invalidReservation
        }
        guard CloudObjectContainerV1.sha256(storedBytes) == expectedSHA256 else {
            throw CloudProtocolError.authenticationFailed
        }
        if let existing = objects[objectID] {
            guard existing.reservationID == reservation.reservationID,
                  existing.storedBytes == storedBytes,
                  existing.sha256 == expectedSHA256 else {
                throw CloudMockStoreErrorV1.objectAlreadyExists
            }
            return
        }

        let (newUploaded, overflow) = record.uploadedByteCount.addingReportingOverflow(
            UInt64(storedBytes.count)
        )
        guard !overflow, newUploaded <= reservation.declaredByteCount else {
            throw CloudMockStoreErrorV1.reservationSizeExceeded
        }
        objects[objectID] = ObjectRecord(
            accountID: reservation.accountID,
            vaultID: reservation.vaultID,
            reservationID: reservation.reservationID,
            storedBytes: storedBytes,
            sha256: expectedSHA256,
            createdAtMilliseconds: nowMilliseconds,
            committed: false
        )
        record.uploadedByteCount = newUploaded
        record.objectIDs.insert(objectID)
        reservations[reservation.reservationID] = record
    }

    func commitObject(
        reservation: CloudMockReservationV1,
        objectID: UUID,
        observedByteCount: UInt64,
        observedSHA256: Data
    ) throws {
        guard let reservationRecord = reservations[reservation.reservationID],
              reservationRecord.token == reservation,
              reservationRecord.finalizedHead == nil,
              var object = objects[objectID],
              object.reservationID == reservation.reservationID else {
            throw CloudMockStoreErrorV1.invalidReservation
        }
        guard UInt64(object.storedBytes.count) == observedByteCount,
              object.sha256 == observedSHA256 else {
            throw CloudProtocolError.authenticationFailed
        }
        object.committed = true
        objects[objectID] = object
    }

    func commitGeneration(
        reservation: CloudMockReservationV1,
        generation: UInt64,
        expectedParent: CloudManifestParentV1?,
        manifestObjectID: UUID,
        manifestSHA256: Data,
        referencedObjectIDs: Set<UUID>
    ) throws -> CloudMockGenerationHeadV1 {
        guard var reservationRecord = reservations[reservation.reservationID],
              reservationRecord.token == reservation else {
            throw CloudMockStoreErrorV1.invalidReservation
        }
        if let finalized = reservationRecord.finalizedHead {
            guard finalized.generation == generation,
                  finalized.manifestObjectID == manifestObjectID,
                  finalized.manifestSHA256 == manifestSHA256,
                  finalized.objectIDs == referencedObjectIDs else {
                throw CloudMockStoreErrorV1.idempotencyConflict
            }
            return finalized
        }
        guard referencedObjectIDs.contains(manifestObjectID),
              referencedObjectIDs == reservationRecord.objectIDs else {
            throw CloudMockStoreErrorV1.objectNotCommitted
        }
        for objectID in referencedObjectIDs {
            guard let object = objects[objectID],
                  object.reservationID == reservation.reservationID,
                  object.committed else {
                throw CloudMockStoreErrorV1.objectNotCommitted
            }
        }
        guard objects[manifestObjectID]?.sha256 == manifestSHA256 else {
            throw CloudProtocolError.authenticationFailed
        }

        let identity = VaultIdentity(accountID: reservation.accountID, vaultID: reservation.vaultID)
        let current = heads[identity]
        if let current {
            guard generation == current.generation + 1,
                  expectedParent?.generation == current.generation,
                  expectedParent?.manifestObjectID == current.manifestObjectID,
                  expectedParent?.storedObjectSHA256 == current.manifestSHA256 else {
                throw CloudMockStoreErrorV1.staleParent
            }
        } else {
            guard generation == 1, expectedParent == nil else {
                throw CloudMockStoreErrorV1.staleParent
            }
        }

        let head = CloudMockGenerationHeadV1(
            accountID: reservation.accountID,
            vaultID: reservation.vaultID,
            generation: generation,
            manifestObjectID: manifestObjectID,
            manifestSHA256: manifestSHA256,
            objectIDs: referencedObjectIDs
        )
        heads[identity] = head
        generations[identity, default: [:]][generation] = head
        reservationRecord.finalizedHead = head
        reservations[reservation.reservationID] = reservationRecord
        return head
    }

    func currentHead(accountID: UUID, vaultID: UUID) -> CloudMockGenerationHeadV1? {
        heads[VaultIdentity(accountID: accountID, vaultID: vaultID)]
    }

    func getObject(
        accountID: UUID,
        vaultID: UUID,
        objectID: UUID
    ) throws -> Data {
        guard let object = objects[objectID],
              object.accountID == accountID,
              object.vaultID == vaultID else {
            throw CloudMockStoreErrorV1.objectNotFound
        }
        guard object.committed else {
            throw CloudMockStoreErrorV1.objectNotCommitted
        }
        return object.storedBytes
    }

    func cancel(_ reservation: CloudMockReservationV1) {
        guard let record = reservations[reservation.reservationID],
              record.token == reservation,
              record.finalizedHead == nil else { return }
        for objectID in record.objectIDs where !isReferenced(objectID) {
            objects.removeValue(forKey: objectID)
        }
        reservations.removeValue(forKey: reservation.reservationID)
        reservationByIdempotencyKey.removeValue(forKey: reservation.idempotencyKey)
    }

    @discardableResult
    func cleanupOrphans(olderThanMilliseconds cutoff: UInt64) -> Int {
        let expiredReservations = reservations.values.filter {
            $0.finalizedHead == nil && $0.createdAtMilliseconds <= cutoff
        }.map(\.token)
        for reservation in expiredReservations {
            cancel(reservation)
        }

        let orphanIDs = objects.compactMap { objectID, object in
            object.createdAtMilliseconds <= cutoff && !isReferenced(objectID) ? objectID : nil
        }
        for objectID in orphanIDs {
            objects.removeValue(forKey: objectID)
        }
        return expiredReservations.count + orphanIDs.count
    }

    func statistics() -> CloudMockStoreStatisticsV1 {
        CloudMockStoreStatisticsV1(
            objectCount: objects.count,
            activeReservationCount: reservations.values.filter { $0.finalizedHead == nil }.count,
            retainedGenerationCount: generations.values.reduce(0) { $0 + $1.count }
        )
    }

#if DEBUG
    func mutateStoredObjectForTesting(objectID: UUID) throws {
        guard var object = objects[objectID], !object.storedBytes.isEmpty else {
            throw CloudMockStoreErrorV1.objectNotFound
        }
        var changed = object.storedBytes
        changed[changed.index(before: changed.endIndex)] ^= 0x01
        object = ObjectRecord(
            accountID: object.accountID,
            vaultID: object.vaultID,
            reservationID: object.reservationID,
            storedBytes: changed,
            sha256: object.sha256,
            createdAtMilliseconds: object.createdAtMilliseconds,
            committed: object.committed
        )
        objects[objectID] = object
    }
#endif

    private func activeReservedByteCount(accountID: UUID) -> UInt64 {
        reservations.values.reduce(0) { partial, record in
            guard record.token.accountID == accountID,
                  record.finalizedHead == nil else { return partial }
            return partial.addingReportingOverflow(record.token.declaredByteCount).overflow
                ? UInt64.max
                : partial + record.token.declaredByteCount
        }
    }

    private func retainedByteCount(accountID: UUID) -> UInt64 {
        var referenced = Set<UUID>()
        for (identity, generationMap) in generations where identity.accountID == accountID {
            for generation in generationMap.values {
                referenced.formUnion(generation.objectIDs)
            }
        }
        return referenced.reduce(0) { partial, objectID in
            guard let object = objects[objectID] else { return partial }
            return partial.addingReportingOverflow(UInt64(object.storedBytes.count)).overflow
                ? UInt64.max
                : partial + UInt64(object.storedBytes.count)
        }
    }

    private func isReferenced(_ objectID: UUID) -> Bool {
        generations.values.contains { generationMap in
            generationMap.values.contains { $0.objectIDs.contains(objectID) }
        }
    }
}
