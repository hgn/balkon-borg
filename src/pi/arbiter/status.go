// The status page at http://borg-pi/ — one glance at what the unit thinks of itself.
//
// Server-rendered HTML, no build step, no framework, no JavaScript. This page has to
// still work in five years from a phone browser in the garden, when the app is broken
// or the phone is someone else's. It is the first thing you open when something is
// wrong, so it leads with what is wrong.
package main

import (
	"fmt"
	"html"
	"sort"
	"strings"
)

var stateColor = map[State]string{
	StateOK:       "#4ade80",
	StateDegraded: "#fbbf24",
	StateMissing:  "#f87171",
	StateDisabled: "#64748b",
}

const statusCSS = `
:root { color-scheme: dark; }
body { background:#0d0a17; color:#efeaff; font:15px/1.5 system-ui,sans-serif;
       margin:0; padding:22px; }
h1 { font-size:19px; margin:0 0 2px; }
p.sub { color:#9d92c4; margin:0 0 22px; font-size:13px; }
h2 { font-size:11px; letter-spacing:.14em; text-transform:uppercase;
     color:#9d92c4; margin:26px 0 10px; }
table { border-collapse:collapse; width:100%; max-width:640px; }
td { padding:9px 10px; border-bottom:1px solid #241d38; vertical-align:top; }
td.name { font-weight:600; width:9em; }
td.when { color:#9d92c4; font-size:12px; text-align:right; white-space:nowrap; }
.dot { display:inline-block; width:9px; height:9px; border-radius:50%;
       margin-right:8px; vertical-align:middle; }
.reason { color:#9d92c4; font-size:13px; }
footer { color:#6d6490; font-size:12px; margin-top:30px; }
`

func dot(s State) string {
	return fmt.Sprintf(`<span class="dot" style="background:%s"></span>`, stateColor[s])
}

// StatusPage renders the whole page as a string. Pure, so it is testable without a
// server: hand it a registry and modes, get HTML.
func StatusPage(reg *Registry, modes *Modes, host string, extra map[string]string) string {
	var b strings.Builder
	b.WriteString("<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">\n")
	b.WriteString(`<meta name="viewport" content="width=device-width,initial-scale=1">` + "\n")
	fmt.Fprintf(&b, "<title>%s status</title><style>%s</style></head>\n<body>\n",
		html.EscapeString(host), statusCSS)
	fmt.Fprintf(&b, "<h1>%s</h1>\n", html.EscapeString(host))
	fmt.Fprintf(&b, `<p class="sub">%s%s</p>`+"\n", dot(reg.Aggregate()),
		html.EscapeString(reg.Summary()))

	b.WriteString("<h2>Capabilities</h2>\n<table>\n")
	for _, c := range reg.All() {
		reason := ""
		if c.Reason != "" {
			reason = fmt.Sprintf(`<div class="reason">%s</div>`, html.EscapeString(c.Reason))
		}
		fmt.Fprintf(&b, "<tr><td class='name'>%s%s</td><td>%s%s</td><td class='when'>%s</td></tr>\n",
			dot(c.State), html.EscapeString(c.Name), html.EscapeString(string(c.State)),
			reason, html.EscapeString(c.Since))
	}
	b.WriteString("</table>\n<h2>Modes</h2>\n<table>\n")
	for _, mode := range AllModes {
		s := modes.Get(mode)
		value := html.EscapeString(s.Submode)
		if s.Chan != "" {
			value += " · " + html.EscapeString(s.Chan)
		}
		if s.Pinned {
			value += " · pinned"
		}
		fmt.Fprintf(&b, "<tr><td class='name'>%s</td><td>%s</td><td class='when'>%s</td></tr>\n",
			html.EscapeString(string(mode)), value, html.EscapeString(s.Since))
	}
	b.WriteString("</table>\n")

	if len(extra) > 0 {
		keys := make([]string, 0, len(extra))
		for k := range extra {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		b.WriteString("<h2>System</h2>\n<table>\n")
		for _, k := range keys {
			fmt.Fprintf(&b, "<tr><td class='name'>%s</td><td colspan='2'>%s</td></tr>\n",
				html.EscapeString(k), html.EscapeString(extra[k]))
		}
		b.WriteString("</table>\n")
	}

	b.WriteString("<footer>Balkon-Borg · reload for the current state</footer>\n</body></html>\n")
	return b.String()
}

// HealthJSON is the same picture as data, for the app when MQTT is not available.
type HealthJSON struct {
	V            int                   `json:"v"`
	State        State                 `json:"state"`
	Summary      string                `json:"summary"`
	Capabilities map[string]Capability `json:"capabilities"`
	Modes        map[string]ModeState  `json:"modes"`
}

func BuildHealthJSON(reg *Registry, modes *Modes) HealthJSON {
	caps := map[string]Capability{}
	for _, c := range reg.All() {
		caps[c.Name] = c
	}
	ms := map[string]ModeState{}
	for mode, s := range modes.All() {
		ms[string(mode)] = s
	}
	return HealthJSON{V: SchemaVersion, State: reg.Aggregate(), Summary: reg.Summary(),
		Capabilities: caps, Modes: ms}
}
