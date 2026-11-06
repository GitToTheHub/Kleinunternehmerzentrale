module WorkflowsHelper
  def workflow_units
    current_workspace&.invoice_units || InvoiceLine::UNIT_CODES.slice(*Workspace::WORKFLOW_DEFAULTS.fetch("units"))
  end

  def default_invoice_unit
    current_workspace&.default_invoice_unit || "HUR"
  end
end
