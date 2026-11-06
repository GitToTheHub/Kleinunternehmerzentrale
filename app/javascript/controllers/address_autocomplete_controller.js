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
    this.selectedStreet = null
  }

  disconnect() {
    clearTimeout(this.timer)
    this.abort?.abort()
  }

  search(event) {
    if (this.filling) return
    // Saved customers and website suggestions dispatch input events for autosave.
    // Only a user's own edits should start an address lookup.
    if (!event?.isTrusted) {
      this.selectedStreet = null
      return this.hide()
    }

    clearTimeout(this.timer)
    this.abort?.abort()
    this.statusTarget.hidden = true
    const query = this.streetTarget.value.trim()
    if (this.selectedStreet) {
      const street = this.selectedStreet.streetName.toLocaleLowerCase("de-DE")
      const typed = query.toLocaleLowerCase("de-DE")
      if (typed !== street && !typed.startsWith(`${street} `)) this.selectedStreet = null
    }
    if (query.length < 4) return this.hide()

    this.timer = setTimeout(() => this.fetchResults(query), 350)
  }

  async fetchResults(query) {
    const selectedStreet = this.selectedStreet
    this.abort?.abort()
    const controller = new AbortController()
    this.abort = controller
    this.statusTarget.textContent = selectedStreet ? "Hausnummern werden gesucht …" : "Suche läuft … das kann einige Sekunden dauern."
    this.statusTarget.hidden = false
    const searchQuery = selectedStreet ? [query, selectedStreet.postalCode, selectedStreet.city].filter(Boolean).join(", ") : query
    const params = new URLSearchParams({ q: searchQuery, limit: "6", lang: "de" })
    params.append("layer", "house")
    if (!selectedStreet) params.append("layer", "street")

    try {
      const response = await fetch(`${this.urlValue}?${params}`, { signal: controller.signal })
      if (controller.signal.aborted) return
      if (!response.ok) return this.hide()

      const { features } = await response.json()
      if (controller.signal.aborted) return
      this.results = features
        .map((feature) => this.toAddress(feature.properties))
        .filter((address) => address.street)
        .filter((address) => !selectedStreet || this.matchesStreet(address, selectedStreet))
      this.statusTarget.hidden = true
      this.render()
    } catch (error) {
      if (error.name !== "AbortError") this.hide()
    }
  }

  toAddress(properties) {
    const street = properties.street || ((properties.osm_key === "highway" || properties.type === "street") ? properties.name : "") || ""
    const houseNumber = String(properties.housenumber || "").trim()
    return {
      street: street ? [street, houseNumber].filter(Boolean).join(" ") : "",
      streetName: street,
      houseNumber,
      postalCode: properties.postcode || "",
      city: properties.city || properties.town || properties.village || properties.district || "",
      country: (properties.countrycode || "").toUpperCase()
    }
  }

  matchesStreet(address, selected) {
    const same = (left, right) => left.trim().toLocaleLowerCase("de-DE") === right.trim().toLocaleLowerCase("de-DE")
    return address.houseNumber && same(address.streetName, selected.streetName) &&
      (!selected.city || same(address.city, selected.city)) &&
      (!selected.postalCode || address.postalCode === selected.postalCode) &&
      (!selected.country || address.country === selected.country)
  }

  render() {
    this.listTarget.replaceChildren()
    this.active = -1
    if (this.results.length === 0) {
      this.hide()
      this.statusTarget.textContent = this.selectedStreet
        ? "Keine Hausnummern für diese Straße gefunden. Bitte ergänze die Hausnummer selbst."
        : "Keine passende Adresse gefunden. Bitte gib Straße und Hausnummer selbst ein."
      this.statusTarget.hidden = false
      return
    }

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
    this.selectedStreet = address
    // Die programmatisch gesetzten Werte dürfen keine neue Suche auslösen.
    this.filling = true
    this.fill("street", address.houseNumber ? address.street : `${address.street} `)
    this.fill("postal_code", address.postalCode)
    this.fill("city", address.city)
    const country = document.getElementById(`invoice_${this.prefixValue}_country`)
    if (country && address.country && [...country.options].some((option) => option.value === address.country)) {
      this.fill("country", address.country)
    }
    this.filling = false
    this.hide()
    if (!address.houseNumber) {
      this.streetTarget.focus()
      const end = this.streetTarget.value.length
      this.streetTarget.setSelectionRange(end, end)
      return this.fetchResults(address.streetName)
    }
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
