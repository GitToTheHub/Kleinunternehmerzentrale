import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async print() {
    const element = document.querySelector('[data-controller~="invoice-pagination"]')
    const pagination = element && this.application.getControllerForElementAndIdentifier(element, "invoice-pagination")
    if (pagination && !(await pagination.ready)) return
    window.print()
  }
}
