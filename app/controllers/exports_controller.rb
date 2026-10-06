class ExportsController < ApplicationController
  def show
    return redirect_to invoices_path, alert: "Es gibt noch nichts zu exportieren." unless current_workspace

    send_data DataExport.new(current_workspace).call,
      filename: "meine-daten-#{Date.current.iso8601}.zip", type: "application/zip", disposition: :attachment
  end
end
