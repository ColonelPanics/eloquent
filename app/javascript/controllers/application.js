import { Application } from "@hotwired/stimulus"
import { Multiselect } from "@wizardhealth/stimulus-multiselect";

const application = Application.start()
application.register('multiselect', Multiselect);

// Configure Stimulus development experience
application.debug = false
window.Stimulus   = application

export { application }
