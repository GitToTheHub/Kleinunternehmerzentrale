import { Controller } from "@hotwired/stimulus"

// Adressvorschläge beim Tippen im Straßenfeld über Photon (OpenStreetMap-Daten, photon.komoot.io).
// Dabei werden die getippten Zeichen und die IP-Adresse an den Dienst übertragen (siehe Datenschutzerklärung).
export default class extends Controller {
  static targets = ["street", "list", "status"]
  static values = { prefix: String, url: { type: String, default: "https://photon.komoot.io/api/" } }

  connect() {
    this.results = []
    this.active = -1
    this.timer = null
  }

  disconnect() {
    clearTimeout(this.timer)
    this.abort?.abort()
  }

  search() {
    if (this.filling) return

    clearTimeout(this.timer)
    this.abort?.abort()
    this.statusTarget.hidden = true
    const query = this.streetTarget.value.trim()
    if (query.length < 4) return this.hide()

    this.timer = setTimeout(() => this.fetchResults(query), 350)
  }

  async fetchResults(query) {
    this.abort?.abort()
    const controller = new AbortController()
    this.abort = controller
    this.statusTarget.hidden = false
    const params = new URLSearchParams({ q: query, limit: "6", lang: "de" })
    params.append("layer", "house")
    params.append("layer", "street")

    try {
      const response = await fetch(`${this.urlValue}?${params}`, { signal: controller.signal })
      if (!response.ok) return this.hide()

      const { features } = await response.json()
      this.results = features.map((feature) => this.toAddress(feature.properties)).filter((address) => address.street)
      this.render()
    } catch (error) {
      if (error.name !== "AbortError") this.hide()
    } finally {
      if (!controller.signal.aborted) this.statusTarget.hidden = true
    }
  }

  toAddress(properties) {
    const street = properties.street || properties.name || ""
    return {
      street: [street, properties.housenumber].filter(Boolean).join(" "),
      postalCode: properties.postcode || "",
      city: properties.city || properties.town || properties.village || properties.district || "",
      country: (properties.countrycode || "").toUpperCase()
    }
  }

  render() {
    this.listTarget.replaceChildren()
    this.active = -1
    if (this.results.length === 0) return this.hide()

    this.results.forEach((address, index) => {
      const item = document.createElement("li")
      item.setAttribute("role", "option")
      item.textContent = [address.street, [address.postalCode, address.city].filter(Boolean).join(" ")].filter(Boolean).join(", ")
      item.addEventListener("mousedown", (event) => {
        event.preventDefault()
        this.choose(index)
      })
      this.listTarget.appendChild(item)
    })
    this.listTarget.hidden = false
    this.streetTarget.setAttribute("aria-expanded", "true")
  }

  keydown(event) {
    if (this.listTarget.hidden) return

    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      const step = event.key === "ArrowDown" ? 1 : -1
      this.highlight((this.active + step + this.results.length) % this.results.length)
    } else if (event.key === "Enter" && this.active >= 0) {
      event.preventDefault()
      this.choose(this.active)
    } else if (event.key === "Escape") {
      this.hide()
    }
  }

  highlight(index) {
    this.active = index
    Array.from(this.listTarget.children).forEach((item, i) => item.classList.toggle("is-active", i === index))
  }

  choose(index) {
    const address = this.results[index]
    // Die programmatisch gesetzten Werte dürfen keine neue Suche auslösen.
    this.filling = true
    this.fill("street", address.street)
    this.fill("postal_code", address.postalCode)
    this.fill("city", address.city)
    const country = document.getElementById(`invoice_${this.prefixValue}_country`)
    if (country && address.country && [...country.options].some((option) => option.value === address.country)) {
      this.fill("country", address.country)
    }
    this.filling = false
    this.hide()
  }

  fill(name, value) {
    const field = document.getElementById(`invoice_${this.prefixValue}_${name}`)
    if (!field || !value) return

    field.value = value
    field.dispatchEvent(new Event("input", { bubbles: true }))
    field.dispatchEvent(new Event("change", { bubbles: true }))
  }

  hide() {
    clearTimeout(this.timer)
    this.abort?.abort()
    this.listTarget.hidden = true
    this.statusTarget.hidden = true
    this.results = []
    this.streetTarget.setAttribute("aria-expanded", "false")
  }
}
