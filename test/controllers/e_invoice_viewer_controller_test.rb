require "test_helper"

class EInvoiceViewerControllerTest < ActionDispatch::IntegrationTest
  test "viewer is available without a workspace and loads its local worker" do
    assert_no_difference [ "Workspace.count", "Invoice.count", "InvoiceDraft.count" ] do
      get e_invoice_viewer_url
    end
    assert_response :success
    assert_select "h1", "E-Rechnung ansehen"
    assert_select "input[type=file][accept*='.xml'][accept*='.pdf']"
    assert_select "main[data-controller='e-invoice-viewer'][data-e-invoice-viewer-worker-url-value*='pdfjs.worker']"
    assert_select "main", /nicht hochgeladen oder gespeichert/
    assert_select "main", /prüft nicht/
    assert_select "article[hidden]"
  end

  test "viewer is linked from the overview and the reception explanation" do
    get invoices_url
    assert_select "a[href=?]", e_invoice_viewer_path, text: "E-Rechnung ansehen"
    get hilfe_url
    assert_select "#e-rechnung a[href=?][target='_blank'][rel='noopener']", e_invoice_viewer_path, count: 1
    assert_select "#e-rechnung p", /Es empfiehlt sich aber, sie für das menschliche Auge lesbar darstellen zu können/
    assert_select "#e-rechnung a[href=?][target='_blank'][rel='noopener']", "https://www.elster.de/eportal/e-rechnung", count: 1
    get e_invoice_viewer_url
    assert_select "a[href=?][target='_blank'][rel='noopener']", "https://www.elster.de/eportal/e-rechnung", text: "E-Rechnungsviewer der Finanzverwaltung in ELSTER"
  end
end
