# KeyHollow TestFlight Readiness

## Already prepared in source

- Native iOS target: KeyHollow
- Bundle identifier: `com.keyhollow.app`
- Minimum iOS version: 17.0
- Version: 0.1.0 (build 1)
- Automatic code-signing mode configured
- Release archive configuration present
- Simulator CI build
- Security unit-test target
- Photos permission strings
- Standard Apple cryptography export declaration configured
- Draft privacy policy, support page, and App Store metadata
- App icon asset catalog with a 1024x1024 source image

## Required from the Apple Developer account

These cannot be stored or guessed in source control and must be supplied through Xcode/App Store Connect:

1. Active Apple Developer Program membership.
2. Apple Developer Team selection for the KeyHollow target.
3. Registration of `com.keyhollow.app` if Apple has not already created it automatically.
4. Signing certificate/provisioning managed by Xcode or App Store Connect.
5. An App Store Connect app record using the final KeyHollow name, subject to name availability in App Store Connect.

## Required product assets before external TestFlight/App Store review

- Publish the included privacy-policy draft at a final HTTPS URL.
- Publish the included support draft at a final HTTPS URL and add the support contact.
- Review and enter the included App Store metadata draft.
- App Store screenshots.
- Age rating answers.
- App privacy questionnaire answers.
- Encryption/export-compliance confirmation based on the final cryptographic implementation.

## Internal TestFlight path

1. Open/generate `KeyHollow.xcodeproj` from `project.yml` using XcodeGen.
2. Select the KeyHollow target and the user's Apple Developer Team.
3. Confirm bundle ID `com.keyhollow.app` is accepted by Apple.
4. Run on a physical iPhone and complete `DEVICE_TEST_PLAN.md` critical cases.
5. Product > Archive using the Release configuration.
6. Validate the archive in Xcode Organizer.
7. Distribute to App Store Connect.
8. Add the build to an internal TestFlight group.
9. Re-run the device-security test plan on the TestFlight-delivered build.

## External TestFlight gate

Do not invite external testers until:

- first-vault setup works on device;
- two or more independent passcodes demonstrably open different vaults;
- Copy and Move behavior has been verified with Apple Photos;
- no Face ID/Touch ID/device-passcode substitute path exists;
- background/app-switcher protection is verified;
- passcode rotation and vault deletion pass real-device testing;
- wrong-passcode throttling is tested;
- no plaintext media leakage is found in the app container;
- KDF performance is benchmarked on the oldest supported iPhone;
- all CI build/security tests are green.

## App Store release gate

Before marketing KeyHollow as a secure/privacy vault product, complete an independent security review of the KDF, key wrapping, vault discovery model, encrypted storage, lifecycle handling, and photo import/delete transaction behavior. Security marketing must accurately state limitations and must not promise absolute coercion, forensic, or compromised-device resistance.
