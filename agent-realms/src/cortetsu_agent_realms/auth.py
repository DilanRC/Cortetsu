"""Capabilities and short-lived credentials for observer and MCP clients.

Secrets live only in process memory and are compared through their SHA-256
digest, so a dump of the store never yields a usable credential.
"""
from __future__ import annotations

import hashlib
import secrets
import threading
import time
from dataclasses import dataclass
from enum import Enum
from typing import Callable, Iterable


class Capability(str, Enum):
    OBSERVE = "observe"   # read state and frames
    CONTROL = "control"   # inject input, launch and close apps or windows
    ADMIN = "admin"       # start and stop the realm

    @classmethod
    def parse(cls, values: Iterable[str]) -> frozenset["Capability"]:
        try:
            return frozenset(cls(v) for v in values)
        except ValueError as exc:
            raise ValueError(f"capacidad desconocida; usa observe, control o admin: {exc}") from exc


class AuthError(Exception):
    pass


def _digest(secret: str) -> bytes:
    return hashlib.sha256(secret.encode()).digest()


@dataclass
class _Grant:
    capabilities: frozenset[Capability]
    created: float
    last_used: float
    expires: float


class CredentialStore:
    """One-use launch tickets that exchange into idle- and age-limited session tokens."""

    def __init__(self, *, ticket_ttl: float = 60.0, session_idle: float = 1800.0,
                 session_max_age: float = 8 * 3600.0, max_sessions: int = 8,
                 clock: Callable[[], float] = time.monotonic):
        self.ticket_ttl = ticket_ttl
        self.session_idle = session_idle
        self.session_max_age = session_max_age
        self.max_sessions = max_sessions
        self._clock = clock
        self._lock = threading.Lock()
        self._tickets: dict[bytes, _Grant] = {}
        self._sessions: dict[bytes, _Grant] = {}

    def issue_ticket(self, capabilities: Iterable[Capability]) -> str:
        now = self._clock()
        ticket = secrets.token_urlsafe(32)
        with self._lock:
            self._expire(now)
            self._tickets[_digest(ticket)] = _Grant(frozenset(capabilities), now, now, now + self.ticket_ttl)
        return ticket

    def redeem(self, ticket: str) -> tuple[str, frozenset[Capability]]:
        now = self._clock()
        with self._lock:
            self._expire(now)
            grant = self._tickets.pop(_digest(ticket), None) if isinstance(ticket, str) else None
            if grant is None:
                raise AuthError("ticket inválido, usado o caducado")
            if len(self._sessions) >= self.max_sessions:
                oldest = min(self._sessions, key=lambda key: self._sessions[key].last_used)
                del self._sessions[oldest]
            token = secrets.token_urlsafe(32)
            self._sessions[_digest(token)] = _Grant(grant.capabilities, now, now,
                                                     now + self.session_max_age)
        return token, grant.capabilities

    def authorize(self, token: str | None, needed: Capability) -> None:
        if not token:
            raise AuthError("falta la credencial")
        now = self._clock()
        key = _digest(token)
        with self._lock:
            self._expire(now)
            # Keys are digests of the secret, so the lookup leaks no prefix timing.
            grant = self._sessions.get(key)
            if grant is None:
                raise AuthError("credencial inválida, revocada o caducada")
            if needed not in grant.capabilities:
                raise AuthError(f"la credencial no concede {needed.value}")
            grant.last_used = now

    def revoke_all(self) -> int:
        with self._lock:
            count = len(self._sessions) + len(self._tickets)
            self._sessions.clear()
            self._tickets.clear()
        return count

    def active_sessions(self) -> int:
        with self._lock:
            self._expire(self._clock())
            return len(self._sessions)

    def last_activity(self) -> float | None:
        with self._lock:
            return max((g.last_used for g in self._sessions.values()), default=None)

    def _expire(self, now: float) -> None:
        for key in [k for k, g in self._tickets.items() if g.expires <= now]:
            del self._tickets[key]
        for key in [k for k, g in self._sessions.items()
                    if g.expires <= now or now - g.last_used >= self.session_idle]:
            del self._sessions[key]
