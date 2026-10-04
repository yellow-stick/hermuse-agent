"""Per-turn local clock for the model (``pre_llm_call`` hook).

Hermes freezes a session's system prompt at creation and keeps only the date
there ("Conversation started: …"); the Bot Chat prompt is even timeless (only
the timezone survives, ``agent/system_prompt.py::_timestamp_line``). Without the
time of day the agent mis-schedules reminders ("demain vers 20h47 (ce soir pour
vous)", "Premier run ce soir" for a run three minutes away). ``pre_llm_call``
context is appended to the current user message on every turn and persisted
with it (``agent/turn_context.py::_collect_pre_llm_call_context``), so each turn
carries the local date, time and timezone of the moment it was sent.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

_WEEKDAYS = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
_MONTHS = ("January", "February", "March", "April", "May", "June", "July",
           "August", "September", "October", "November", "December")


def _day(value: datetime) -> str:
    return f"{_WEEKDAYS[value.weekday()]} {value.day} {_MONTHS[value.month - 1]} {value.year}"


def _zone(now: datetime, name: str) -> str:
    """``Europe/Berlin, UTC+02:00`` (IANA name when known, else the abbreviation)."""
    offset = now.strftime("%z")
    utc = f"UTC{offset[:3]}:{offset[3:]}" if offset else ""
    label = name or getattr(now.tzinfo, "key", "") or now.strftime("%Z")
    return ", ".join(part for part in (label, utc) if part)


def clock_line(now: datetime, zone_name: str = "") -> str:
    """One line with the local weekday, date, time, timezone and tomorrow's date.
    English names so the line never depends on the server locale."""
    tomorrow = now + timedelta(days=1)
    return (
        f"Local time now: {_day(now)}, {now:%H:%M} ({_zone(now, zone_name)}; "
        f"ISO {now:%Y-%m-%dT%H:%M}). Tomorrow is {_day(tomorrow)}."
    )


def _local_now() -> tuple[datetime, str]:
    """Hermes' configured timezone (``timezone:`` in config.yaml), else server-local."""
    try:
        from hermes_time import get_timezone_name, now

        return now(), get_timezone_name()
    except Exception:  # Hermes not importable (unit tests of the store) or a config error
        return datetime.now().astimezone(), ""


def pre_llm_call(**kwargs: Any) -> dict[str, str]:
    now, zone_name = _local_now()
    return {"context": clock_line(now, zone_name)}
