require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "Datenschutzerklärung nennt den Adressdienst Photon" do
    get datenschutz_url
    assert_response :success
    assert_select "h1", "Datenschutzerklärung"
    assert_select "main", /Photon/
    assert_select "main", /IP-Adresse/
  end

  test "Startseite wird angezeigt" do
    get root_url
    assert_response :success
    assert_select "h1", /Einnahmen und Ausgaben/
    assert_select "p", /Rechnungen schreiben, Belege und Zahlungen erfassen und deine EÜR vorbereiten/
    assert_select "p", /Für Selbstständige, die die Kleinunternehmerregelung nutzen/
    assert_select "h2", "Der Papierkram, der zu deinem Geschäft gehört"
    assert_select ".guide-card__title", "Rechnungen schreiben"
    assert_select ".guide-card__title", "Belege und Zahlungen erfassen"
    assert_select ".guide-card__title", "EÜR vorbereiten"
    assert_select "h2", "Musst du jeden Tag komplizierte Buchhaltung machen?"
    assert_select "main", /Im Alltag wird das oft „Buchhaltung“ genannt/
    assert_select "main", /nicht jeden Vorgang doppelt auf Konten buchen/
    assert_select "main", /Kontenrahmen wie SKR03/
    assert_select "main", /Das allein bedeutet nicht, dass du eine doppelte Buchführung machen musst/
    assert_select "main", /Für die meisten kleinen Einzelunternehmen und Freiberufler ist das der übliche Weg/
    assert_select "main", /Einzelunternehmen kann zum Beispiel zu groß werden/
    assert_select "main", /eine GmbH muss grundsätzlich eine Bilanz erstellen/
    assert_select "main", /Sie kann trotzdem die Kleinunternehmerregelung nutzen/
    assert_select "h2", "Was ist ein Einzelunternehmen?"
    assert_select "main", /Die Kleinunternehmerregelung betrifft die Umsatzsteuer; „Einzelunternehmen“ bedeutet/
    assert_select "main", /grundsätzlich auch mit deinem Privatvermögen/
    assert_select "h2", "Wir helfen auch beim Start"
    assert_select "h2", "Die Kleinunternehmerregelung – kurz erklärt"
    assert_select "p", /Du schreibst Rechnungen ohne Umsatzsteuer/
    assert_select "p", /Umsatzsteuer auf geschäftliche Einkäufe nicht zurück/
  end

  test "Gründungskosten-Seite wird angezeigt" do
    get gruendungskosten_url
    assert_response :success
    assert_select "h1", /Kleingewerbe/
    assert_select "td", /kostenlos/
  end

  test "Gewerbeanmeldung-Seite wird angezeigt" do
    get gewerbeanmeldung_url
    assert_response :success
    assert_select "h1", /Gewerbeanmeldung/
    assert_select "h2", "Gewerbe oder freier Beruf?"
    assert_select "h2", "Was bedeutet Einzelunternehmen?"
    assert_select "h2", "Einfache Buchführung oder doppelte Buchführung?"
    assert_select "main", /Kontenrahmen wie SKR03 an/
    assert_select "main", /Eine solche Sortierung allein heißt noch nicht, dass du doppelte Buchführung machen musst/
    assert_select "main", /entscheidet nicht darüber, ob du eine EÜR machen darfst/
    assert_select "main", /Sie kann trotzdem die Kleinunternehmerregelung nutzen/
    assert_select "h2", "Was müssen Freiberufler aufschreiben und abgeben?"
    assert_select "p", /Die Kleinunternehmerregelung ändert daran nichts/
    assert_select "main", /In diesem Fragebogen kannst du auch wählen/
    assert_select "main", /grundsätzlich mindestens fünf Jahre/
  end

  test "Vorteile-Seite wird angezeigt" do
    get vorteile_url
    assert_response :success
    assert_select "h1", "Vorteile der Kleinunternehmerregelung"
    assert_select "h2", "Was bedeutet die Regelung für dich?"
    assert_select "h2", "Was Selbstständige außerdem wissen sollten"
    assert_select "h3", "Du kannst bei der Gründung wählen"
    assert_select "main", /Wenn du die Voraussetzungen erfüllst, kannst du bei der Gründung/
    assert_select "h3", "Einkommensteuer: Es zählt vor allem dein Gewinn"
    assert_select "h3", "Krankenversicherung: Es gibt einen Mindestbeitrag"
    assert_select "h3", "GKV oder private Krankenversicherung?"
    assert_select "main", /Im normalen Alltag musst du keine regelmäßigen Meldungen zur Umsatzsteuer abgeben/
    assert_select "main", /Software-Abo oder Online-Werbung/
    assert_select "main", /selbst berechnen, melden und bezahlen/
    assert_select "main", /Er gilt für alle Menschen, nicht nur für Kleinunternehmer/
    assert_select "main", /Das ist kein Geld, das du wirklich verdient hast/
    assert_select "main", /Der Mindestbetrag kann sich jedes Jahr ändern/
    assert_select "strong", /Du schreibst deinen Kundinnen und Kunden Rechnungen ohne Umsatzsteuer/
    assert_select "strong", /Umsatzsteuer auf geschäftliche Einkäufe nicht zurück/
  end
end
