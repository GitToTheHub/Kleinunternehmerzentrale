import { readFileSync } from "node:fs"
import { runInNewContext } from "node:vm"
import test from "node:test"
import assert from "node:assert/strict"

const source = readFileSync(new URL("../../app/javascript/controllers/invoice_pagination_controller.js", import.meta.url), "utf8")
function setup({ fail = false, count = 2 } = {}) {
  const pages = Array.from({ length: count }, () => ({ append(footer) { this.footer = footer } }))
  const previewer = { chunker: { hooks: { renderNode: { register() {} }, afterPageLayout: { register() {} } } }, polisher: { destroy() {} }, async preview() { if (fail) throw new Error("Rendering failed") } }
  const Pagination = runInNewContext(source.replace(/^import .*\n/, "").replace("export default class", "globalThis.Pagination = class").replace('import("pagedjs")', "Promise.resolve({ Previewer: MockPreviewer })") + "\nPagination", {
    Controller: class {}, MockPreviewer: class { constructor() { return previewer } },
    window: { location: { href: "https://example.test/invoices/1" } },
    document: { body: { classList: { contains: () => false } }, fonts: { ready: Promise.resolve() }, createDocumentFragment: () => ({ append() {} }), createElement: () => ({ style: {}, append() {} }) },
  })
  const controller = new Pagination()
  controller.sourceTarget = { hidden: false, querySelectorAll: () => [], cloneNode: () => ({ removeAttribute() {}, querySelector: () => ({ style: {}, prepend() {} }) }) }
  controller.pagesTarget = { querySelectorAll: () => pages, replaceChildren() { this.cleared = true }, classList: { add() {}, remove() {} } }
  controller.statusTarget = { hidden: false }
  return { controller, pages }
}

test("each rendered page receives its own number and total as actual text", async () => {
  const { controller, pages } = setup()
  controller.connect()
  assert.equal(await controller.ready, true)
  assert.equal(pages[0].footer.textContent, "Seite 1 von 2")
  assert.equal(pages[1].footer.textContent, "Seite 2 von 2")
  assert.equal(controller.sourceTarget.hidden, true)
  assert.equal(controller.statusTarget.hidden, true)
})

test("failed pagination keeps the original invoice and reports the failure", async () => {
  const { controller } = setup({ fail: true })
  controller.connect()
  assert.equal(await controller.ready, false)
  assert.equal(controller.sourceTarget.hidden, false)
  assert.equal(controller.pagesTarget.cleared, true)
  assert.match(controller.statusTarget.textContent, /Bitte lade die Seite erneut/)
})

test("leaving before the library loads cancels pagination without hiding the invoice", async () => {
  const { controller } = setup()
  controller.connect()
  controller.disconnect()
  assert.equal(await controller.ready, false)
  assert.equal(controller.sourceTarget.hidden, false)
})


test("continued tables receive their column headers before further content is laid out", () => {
  const { controller } = setup()
  const cloned = { dataset: {} }
  const body = {}
  const header = { cloneNode(deep) { assert.equal(deep, true); return cloned } }
  const table = {
    querySelector(selector) { return selector === "thead" ? this.header : body },
    insertBefore(node, before) { assert.equal(before, body); this.header = node; this.insertions = (this.insertions || 0) + 1 }
  }
  const original = { nodeType: 1, closest: () => ({ querySelector: () => header }) }
  const rendered = { nodeType: 1, closest: () => table }
  controller.repeatTableHeader(rendered, original)
  controller.repeatTableHeader(rendered, original)
  assert.equal(table.header, cloned)
  assert.equal(table.insertions, 1)
  // A break inside a description can start at a text node rather than an element.
  table.header = null
  controller.repeatTableHeader({ nodeType: 3, parentElement: rendered }, { nodeType: 3, parentElement: original })
  assert.equal(table.insertions, 2)
})


test("totals alone do not receive a repeated positions header", () => {
  const { controller } = setup()
  const table = { querySelector: () => null, insertBefore() { assert.fail("A total is not a position") } }
  const original = {
    nodeType: 1,
    closest(selector) {
      return selector === ".invoice-table" ? { querySelector: () => ({ cloneNode() { assert.fail("Totals need no column header") } }) } : null
    }
  }
  controller.repeatTableHeader({ nodeType: 1, closest: () => table }, original)
})

test("a repeated header left behind after its row moves to the next page is removed", () => {
  const { controller } = setup()
  const makeHeader = (texts) => ({
    closest: () => ({ querySelectorAll: () => texts.map(textContent => ({ textContent })) }),
    remove() { this.removed = true }
  })
  const empty = makeHeader(["  "])
  const continuation = makeHeader(["Fortsetzung der Beschreibung"])
  controller.removeOrphanedHeaders({ querySelectorAll: () => [empty, continuation] })
  assert.equal(empty.removed, true)
  assert.equal(continuation.removed, undefined)
})

test("embedded preview fits A4 pages to the available width without enlarging them", () => {
  const { controller } = setup()
  controller.resizeObserver = {}
  controller.element = { clientWidth: 340 }
  controller.pagesTarget.querySelector = () => ({ offsetWidth: 794 })
  controller.pagesTarget.style = {}
  controller.fitPreview()
  assert.equal(controller.pagesTarget.style.zoom, 340 / 794)
  controller.element.clientWidth = 1000
  controller.fitPreview()
  assert.equal(controller.pagesTarget.style.zoom, 1)
})
