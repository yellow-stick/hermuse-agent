"""The agent's computer: one Docker container per Hermes profile (Chromium with
CDP on an XFCE desktop, streamed by ``screend``), exposed to Hermes as the
``hermuse`` browser provider and to Hermuse UIs through the dashboard routes.

Imported both as ``hermes_plugins.hermuse.computer`` (agent process) and as the
top-level package ``computer`` (dashboard backend and tests put the plugin root
on ``sys.path``), so modules here import each other relatively and reach
``store`` through :mod:`.state`.
"""
