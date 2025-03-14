import { Multiselect } from "@wizardhealth/stimulus-multiselect";

const getCSRFParam = () => document.querySelector("meta[name='csrf-token']").getAttribute("content");

export default class extends Multiselect {

  // Override the less-than-useful superclass implementation so we can actually
  // access the data we need, etc...
  addableEvent() {
    super.addableEvent();

    console.log(this.searchTarget.value, this.addableUrlValue);

    fetch(this.addableUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": getCSRFParam()
      },
      body: JSON.stringify({ player: { name: this.searchTarget.value } })
    }).then(
      result => {
        result.json().then(
          json => {
            if (!json.errors) {
              this.addAddableItem(json);
            }
          }
        )
      }
    )
  }

}
