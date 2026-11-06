module ApplicationHelper
  BUTTON_ICON_PATHS = {
    add: "M12 5v14M5 12h14",
    edit: "m16 3 5 5-12 12-6 1 1-6ZM14 5l5 5",
    back: "M20 12H4m7-7-7 7 7 7",
    forward: "M4 12h16m-7-7 7 7-7 7",
    check: "M22 11v1a10 10 0 1 1-6-9M22 4 12 14l-3-3",
    download: "M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5",
    upload: "M12 16V4m-5 5 5-5 5 5M4 17v4h16v-4",
    print: "M7 8V3h10v5M7 17H3V9h18v8h-4M7 14h10v7H7ZM17 11h1",
    refresh: "M20 7a9 9 0 0 0-15-2L2 8m0-5v5h5M4 17a9 9 0 0 0 15 2l3-3m0 5v-5h-5",
    search: "M21 21l-6-6M17 10a7 7 0 1 1-14 0 7 7 0 0 1 14 0Z",
    login: "M14 3h7v18h-7M3 12h13m-5-5 5 5-5 5",
    logout: "M10 3H3v18h7M10 12h11m-5-5 5 5-5 5",
    user_add: "M16 21v-2a6 6 0 0 0-12 0v2M14 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0ZM20 8v6m-3-3h6",
    book: "M3 3h6a4 4 0 0 1 3 1 4 4 0 0 1 3-1h6v17h-6a4 4 0 0 0-3 1 4 4 0 0 0-3-1H3ZM12 4v17",
    asset: "m3 7 9-4 9 4-9 4ZM3 7v10l9 4 9-4V7M12 11v10",
    external: "M14 3h7v7M21 3l-11 11M10 3H3v18h18v-7",
    heart: "M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z",
    info: "M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0ZM12 11v6M12 7h.01",
    undo: "M3 10h11a6 6 0 0 1 0 12M3 10l5-5M3 10l5 5",
    indent: "M10 4h11M10 9h11M10 15h11M10 20h11M3 8l4 4-4 4",
    outdent: "M10 4h11M10 9h11M10 15h11M10 20h11M7 8l-4 4 4 4",
    link: "m10 13 4-4M8 16l-1 1a4 4 0 0 1-6-6l5-5a4 4 0 0 1 6 0M12 18a4 4 0 0 0 6 0l5-5a4 4 0 0 0-6-6l-1 1",
    calculator: "M5 2h14v20H5ZM8 5h8v4H8ZM8 13h1M12 13h1M16 13h.01M8 17h1M12 17h1M16 17h.01"
  }.freeze

  def button_icon(name)
    key = name.to_sym
    path = BUTTON_ICON_PATHS[key] || InvoicesHelper::ACTION_ICON_PATHS[key] || InvoicesHelper::FIELD_ICON_PATHS.fetch(key)
    content_tag(:svg, tag.path(d: path), class: "button-icon", width: 18, height: 18,
      viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": 1.8,
      "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": true, focusable: false)
  end

  def button_label(text, icon:)
    safe_join([ button_icon(icon), tag.span(text, class: "button-label", data: { button_label: true }) ])
  end
end
