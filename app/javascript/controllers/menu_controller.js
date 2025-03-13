import { Controller } from "@hotwired/stimulus";
import { enter, leave } from "el-transition";

export default class extends Controller {
  static targets = ["button", "menu"];
  static values = { isOpen: { type: Boolean, default: false } };

  toggle(evt) {
    this.isOpenValue = !this.isOpenValue;
    evt.stopPropagation();
  }

  close() {
    this.isOpenValue = false;
  }

  isOpenValueChanged(isOpen) {
    if (this.hasMenuTarget) {
      if (isOpen) {
        enter(this.menuTarget);
      }
      else {
        leave(this.menuTarget);
      }
    }
  }
}
