async function lookupPA() {
  const address = document.getElementById("addressInput").value;
  const resultBox = document.getElementById("result");

  if (!address) {
    resultBox.innerHTML = "Please enter a valid address.";
    return;
  }

  const apiKey = "YOUR_API_KEY"; // Replace with your real API key
  const geocodeURL = `https://maps.googleapis.com/maps/api/geocode/json?address=${encodeURIComponent(address)}&key=${apiKey}`;

  try {
    const response = await fetch(geocodeURL);
    const data = await response.json();

    if (data.status !== "OK") {
      resultBox.innerHTML = "Address not found.";
      return;
    }

    const components = data.results[0].address_components;
    const countyComponent = components.find(c => c.types.includes("administrative_area_level_2"));
    const formattedAddress = data.results[0].formatted_address;

    if (!countyComponent) {
      resultBox.innerHTML = "County not found.";
      return;
    }

    const county = countyComponent.long_name;

    if (county.includes("Palm Beach")) {
      const redirectURL = `https://www.pbcgov.org/papa/Asps/PropertyDetail/Search.aspx?searchby=address&searchstring=${encodeURIComponent(address)}`;
      window.open(redirectURL, "_blank");
      resultBox.innerHTML = `Palm Beach County detected. <a href="${redirectURL}" target="_blank">Open PA Search</a>`;
    } else {
      resultBox.innerHTML = `
        County detected: <strong>${county}</strong><br />
        <em>This county may not support full automation yet. Please search manually on the local PA website.</em><br />
        Address: ${formattedAddress}
      `;
    }

  } catch (err) {
    console.error(err);
    resultBox.innerHTML = "Something went wrong.";
  }
}
