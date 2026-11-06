import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const requests = []
const listeners = {}
let confirmDeletion = true
let saveSucceeds = true
let fetchWait
const source = readFileSync(new URL("../../app/javascript/controllers/invoice_draft_controller.js", import.meta.url), "utf8")
const InvoiceDraft = runInNewContext(source.replace(/^import .*\n/, "").replace("export default class", "globalThis.InvoiceDraft = class") + "\nInvoiceDraft", {
  Controller: class {}, AbortController, FormData: class { constructor(element) { this.element = element } },
  document: { documentElement: {} },
  clearTimeout(id) { if (id) delete listeners.timer },
  setTimeout(callback, delay) { listeners.timer = callback; listeners.delay = delay; return 1 },
  fetch: async (url, options) => { requests.push({ ...options, url }); await fetchWait; return { ok: saveSucceeds, json: async () => ({ draft_id: 10, save_url: "/rechnungen/entwuerfe/10", delete_url: "/rechnungen/entwuerfe/10", edit_url: "/rechnungen/entwuerfe/10/bearbeiten", preview_url: "/rechnungen/entwuerfe/10/vorschau" }) } },
  window: {
    confirm() { return confirmDeletion },
    location: { assign(url) { listeners.destination = url } },
    history: { replaceState(_state, _title, url) { listeners.url = url } },
    addEventListener(name, callback) { listeners[name] = callback },
    removeEventListener(name) { delete listeners[name] },
  },
})

function setup() {
  confirmDeletion = true
  saveSucceeds = true
  fetchWait = undefined
  delete listeners.destination
  delete listeners.previewTarget
  delete listeners.previewClosed
  delete listeners.previewDestination
  const controller = new InvoiceDraft()
  controller.element = { form: true }
  controller.dispatch = (name, options) => { if (name === "preview") listeners.previewDestination = options.detail.url }
  controller.urlValue = "/rechnungen/entwurf"
  controller.statusTarget = { textContent: "" }
  controller.hasLeaveTarget = true
  controller.leaveTarget = { href: "/rechnungen", textContent: "Später" }
  controller.hasDiscardLabelTarget = true
  controller.discardLabelTarget = {}
  controller.deleteUrlValue = "/rechnungen/entwurf"
  controller.connect()
  return controller
}

function backEvent() {
  return { currentTarget: { href: "/rechnungen" }, preventDefault() { this.prevented = true } }
}

test("back saves immediately and waits before loading the overview", async () => {
  const controller = setup()
  let finish
  fetchWait = new Promise(resolve => { finish = resolve })
  controller.schedule()
  const event = backEvent()
  const leaving = controller.back(event)
  assert.equal(event.prevented, true)
  assert.equal(listeners.timer, undefined)
  assert.equal(listeners.destination, undefined)
  finish()
  await leaving
  assert.equal(listeners.destination, "/rechnungen")
  assert.equal(controller.skipSaveOnLeave, true)
})

test("back waits for a running save and then saves newer edits without aborting", async () => {
  const controller = setup()
  let finish
  fetchWait = new Promise(resolve => { finish = resolve })
  const count = requests.length
  const saving = controller.save()
  const firstRequest = requests.at(-1)
  controller.schedule()
  const leaving = controller.back(backEvent())
  assert.equal(requests.length, count + 1)
  assert.equal(firstRequest.signal.aborted, false)
  assert.equal(listeners.destination, undefined)
  finish()
  await saving
  await leaving
  assert.equal(requests.length, count + 2)
  assert.equal(listeners.destination, "/rechnungen")
})

test("back keeps the form open on failure and allows retrying", async () => {
  const controller = setup()
  controller.schedule()
  saveSucceeds = false
  await controller.back(backEvent())
  assert.equal(listeners.destination, undefined)
  assert.equal(controller.pending, true)
  assert.equal(controller.statusTarget.textContent, "Entwurf konnte nicht gespeichert werden")
  saveSucceeds = true
  await controller.back(backEvent())
  assert.equal(listeners.destination, "/rechnungen")
})

test("back also waits for a newer save already queued by the autosave timer", async () => {
  const controller = setup()
  let finishFirst
  let finishSecond
  fetchWait = new Promise(resolve => { finishFirst = resolve })
  const first = controller.save()
  controller.schedule()
  const queued = controller.save()
  const leaving = controller.back(backEvent())
  fetchWait = new Promise(resolve => { finishSecond = resolve })
  finishFirst()
  await first
  await Promise.resolve()
  assert.equal(listeners.destination, undefined)
  finishSecond()
  await queued
  await leaving
  assert.equal(listeners.destination, "/rechnungen")
})

test("back leaves an unchanged form without creating an empty draft", async () => {
  const controller = setup()
  const count = requests.length
  await controller.back(backEvent())
  assert.equal(requests.length, count)
  assert.equal(listeners.destination, "/rechnungen")
})

test("leaving also saves edits made while the final save is running", async () => {
  const controller = setup()
  let finish
  fetchWait = new Promise(resolve => { finish = resolve })
  controller.schedule()
  const count = requests.length
  const leaving = controller.back(backEvent())
  controller.schedule()
  finish()
  await leaving
  assert.equal(requests.length, count + 2)
  assert.equal(controller.pending, false)
  assert.equal(listeners.destination, "/rechnungen")
})

test("preview waits for all edits to save and then opens the saved draft in the popover", async () => {
  const controller = setup()
  controller.hasDraftIdTarget = true
  controller.draftIdTarget = { value: "" }
  let finish
  fetchWait = new Promise(resolve => { finish = resolve })
  const submitter = { dataset: { invoicePreview: "true" }, formAction: "/rechnungen/vorschau", formTarget: "_blank" }
  controller.schedule()
  const event = { submitter, preventDefault() { this.prevented = true } }
  const preparing = controller.prepareSubmit(event)
  assert.equal(event.prevented, true)
  assert.equal(listeners.previewDestination, undefined)
  controller.schedule()
  finish()
  await preparing
  assert.equal(controller.pending, false)
  assert.equal(controller.draftIdTarget.value, 10)
  assert.equal(listeners.previewDestination, "/rechnungen/entwuerfe/10/vorschau")
  assert.equal(submitter.formTarget, "_blank")
  assert.equal(controller.skipSaveOnLeave, undefined)
})

test("preview stays in the form and does not open a preview if saving fails", async () => {
  const controller = setup()
  await controller.save()
  let submitted = false
  controller.element.requestSubmit = () => { submitted = true }
  controller.schedule()
  saveSucceeds = false
  await controller.prepareSubmit({ submitter: { dataset: { invoicePreview: "true" }, formAction: "/rechnungen/vorschau", formTarget: "_blank" }, preventDefault() {} })
  assert.equal(submitted, false)
  assert.equal(listeners.previewDestination, undefined)
  assert.equal(controller.pending, true)
  assert.equal(controller.preparingPreview, false)
  assert.equal(controller.statusTarget.textContent, "Entwurf konnte nicht gespeichert werden")
})

test("repeated previews without edits reopen the popover without another save", async () => {
  const controller = setup()
  await controller.save()
  const count = requests.length
  for (let click = 0; click < 3; click++) {
    delete listeners.previewDestination
    const event = { submitter: { dataset: { invoicePreview: "true" }, formAction: "/rechnungen/vorschau" }, preventDefault() { this.prevented = true } }
    await controller.prepareSubmit(event)
    assert.equal(event.prevented, true)
    assert.equal(listeners.previewDestination, "/rechnungen/entwuerfe/10/vorschau")
  }
  assert.equal(requests.length, count)
})

test("a reopened draft obtains its preview URL before navigating", async () => {
  const controller = setup()
  controller.persistedValue = true
  controller.urlValue = "/rechnungen/entwuerfe/10"
  const count = requests.length
  await controller.prepareSubmit({ submitter: { dataset: { invoicePreview: "true" }, formAction: "/rechnungen/vorschau" }, preventDefault() {} })
  assert.equal(requests.length, count + 1)
  assert.equal(requests.at(-1).url, "/rechnungen/entwuerfe/10")
  assert.equal(listeners.previewDestination, "/rechnungen/entwuerfe/10/vorschau")
})

test("saving gives the form its own reloadable address", async () => {
  const controller = setup()
  controller.hasDraftIdTarget = true
  controller.draftIdTarget = { value: "" }
  await controller.save()
  assert.equal(listeners.url, "/rechnungen/entwuerfe/10/bearbeiten")
  assert.equal(controller.draftIdTarget.value, 10)
  await controller.save()
  assert.equal(requests.at(-1).url, "/rechnungen/entwuerfe/10")
})

test("changes are saved and a pending change is flushed when leaving", async () => {
  const controller = setup()
  controller.schedule()
  assert.equal(controller.pending, true)
  assert.equal(controller.statusTarget.textContent, "Ungespeicherte Änderungen")

  await controller.save(true)
  assert.equal(requests.at(-1).method, "PATCH")
  assert.equal(requests.at(-1).keepalive, true)
  assert.equal(controller.statusTarget.textContent, "Entwurf gespeichert")
})

test("typing shows unsaved changes and restarts the one second delay", async () => {
  const controller = setup()
  await controller.save()
  const requestCount = requests.length
  let previousTimer
  for (let index = 0; index < 3; index++) {
    controller.schedule()
    assert.equal(listeners.delay, 1000)
    assert.notEqual(listeners.timer, previousTimer)
    assert.equal(controller.statusTarget.textContent, "Ungespeicherte Änderungen")
    previousTimer = listeners.timer
  }
  assert.equal(requests.length, requestCount)
  const saving = listeners.timer()
  assert.equal(controller.statusTarget.textContent, "Ungespeicherte Änderungen")
  await saving
  assert.equal(requests.length, requestCount + 1)
  assert.equal(controller.statusTarget.textContent, "Entwurf gespeichert")
})

test("a save error is shown and new edits can be saved again", async () => {
  const controller = setup()
  saveSucceeds = false
  await controller.save()
  assert.equal(controller.statusTarget.textContent, "Entwurf konnte nicht gespeichert werden")
  controller.schedule()
  assert.equal(controller.statusTarget.textContent, "Ungespeicherte Änderungen")
  saveSucceeds = true
  await controller.save()
  assert.equal(controller.statusTarget.textContent, "Entwurf gespeichert")
})

test("discard cancels a pending save and deletes without saving", async () => {
  const controller = setup()
  controller.schedule()
  const count = requests.length
  await controller.discard(backEvent())

  assert.equal(controller.pending, false)
  assert.equal(controller.skipSaveOnLeave, true)
  assert.equal(requests.length, count + 1)
  assert.equal(requests.at(-1).method, "DELETE")
  assert.equal(listeners.destination, "/rechnungen")
})

test("an empty new form can be cancelled without saving or deleting a draft", async () => {
  const controller = setup()
  const count = requests.length
  assert.equal(controller.leaveTarget.hidden, true)
  assert.equal(controller.discardLabelTarget.textContent, "Abbrechen")
  await controller.discard(backEvent())
  assert.equal(requests.length, count)
  assert.equal(listeners.destination, "/rechnungen")
})

test("actions change after editing and after a successful save", async () => {
  const controller = setup()
  controller.schedule()
  assert.equal(controller.leaveTarget.hidden, false)
  assert.equal(controller.leaveTarget.textContent, "Später")
  assert.equal(controller.discardLabelTarget.textContent, "Verwerfen")
  await controller.save()
  assert.equal(controller.leaveTarget.textContent, "Später")
  assert.equal(controller.deleteUrlValue, "/rechnungen/entwuerfe/10")
})

test("a reopened draft can be deleted even without edits", async () => {
  const controller = setup()
  controller.persistedValue = true
  controller.hasContent = true
  controller.deleteUrlValue = "/rechnungen/entwuerfe/10"
  controller.updateActions()
  assert.equal(controller.leaveTarget.hidden, false)
  assert.equal(controller.discardLabelTarget.textContent, "Verwerfen")
  await controller.discard(backEvent())
  assert.equal(requests.at(-1).url, "/rechnungen/entwuerfe/10")
  assert.equal(requests.at(-1).method, "DELETE")
})

test("deleting waits for the first save and then deletes its returned ID", async () => {
  const controller = setup()
  controller.schedule()
  let finish
  fetchWait = new Promise(resolve => { finish = resolve })
  const count = requests.length
  const saving = controller.save()
  const deleting = controller.discard(backEvent())
  assert.equal(requests.length, count + 1)
  assert.equal(requests.at(-1).signal.aborted, false)
  assert.equal(listeners.destination, undefined)
  finish()
  await saving
  await deleting
  assert.equal(requests.length, count + 2)
  assert.equal(requests.at(-1).method, "DELETE")
  assert.equal(requests.at(-1).url, "/rechnungen/entwuerfe/10")
  assert.equal(listeners.destination, "/rechnungen")
})

test("a delete error keeps the form available for saving or retrying", async () => {
  const controller = setup()
  controller.schedule()
  saveSucceeds = false
  await controller.discard(backEvent())
  assert.equal(listeners.destination, undefined)
  assert.equal(controller.skipSaveOnLeave, false)
  assert.equal(controller.statusTarget.textContent, "Entwurf konnte nicht gelöscht werden")
  saveSucceeds = true
  await controller.discard(backEvent())
  assert.equal(listeners.destination, "/rechnungen")
})

test("typing in the website lookup does not mark the draft as changed", () => {
  const controller = setup()
  const hint = controller.statusTarget.textContent
  controller.schedule({ target: { closest: () => ({}) } })
  assert.equal(controller.pending, undefined)
  assert.equal(controller.statusTarget.textContent, hint)
})

test("website edits leave pending invoice changes and their save timer intact", () => {
  const controller = setup()
  controller.schedule({ target: { closest: () => null } })
  const timer = listeners.timer
  controller.schedule({ target: { closest: () => ({}) } })
  assert.equal(controller.pending, true)
  assert.equal(listeners.timer, timer)
})

test("cancelling deletion keeps pending edits and autosave intact", async () => {
  const controller = setup()
  controller.schedule()
  const count = requests.length
  const timer = listeners.timer
  confirmDeletion = false
  await controller.discard(backEvent())
  assert.equal(requests.length, count)
  assert.equal(controller.pending, true)
  assert.equal(listeners.timer, timer)
  assert.equal(controller.discarding, undefined)
  assert.equal(listeners.destination, undefined)
})

test("Ctrl+S and Cmd+S save pending edits without leaving or submitting", async () => {
  for (const modifier of ["ctrlKey", "metaKey"]) {
    const controller = setup()
    controller.schedule()
    const event = { key: "s", [modifier]: true, preventDefault() { this.prevented = true } }
    const count = requests.length
    await controller.saveShortcut(event)
    assert.equal(event.prevented, true)
    assert.equal(requests.length, count + 1)
    assert.equal(controller.pending, false)
    assert.equal(controller.statusTarget.textContent, "Entwurf gespeichert")
    assert.equal(listeners.destination, undefined)
  }
})

test("save shortcut keeps failed edits available and does not intercept other keys", async () => {
  const controller = setup()
  controller.schedule()
  saveSucceeds = false
  const event = { key: "s", metaKey: true, preventDefault() { this.prevented = true } }
  await controller.saveShortcut(event)
  assert.equal(event.prevented, true)
  assert.equal(controller.pending, true)
  assert.equal(controller.statusTarget.textContent, "Entwurf konnte nicht gespeichert werden")
  const other = { key: "s", preventDefault() { this.prevented = true } }
  await controller.saveShortcut(other)
  assert.equal(other.prevented, undefined)
})
