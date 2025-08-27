# Archived Documentation

This directory contains documentation that is no longer part of the active development focus.

## Why Archived?

The library has pivoted to a focused, REST-only approach with:
- **Exchanges**: Binance and Bybit only (80%+ of volume)
- **Features**: Market data + trading endpoints only
- **Architecture**: Configurable compile-time endpoint selection
- **Use cases**: Position monitoring, hedging, portfolio management (not HFT)

## Archived Files

- `AI-IMPLEMENTATION.md` - Original broad implementation plan (5+ exchanges, WebSocket, etc.)
- `AI-REVIEW.md` - Review checklist for the broader scope
- `bybit_api_tickets.md` - Detailed Bybit API issues (still partially relevant)
- `WEBSOCKET_INTEGRATION_PLAN.md` - WebSocket implementation plan (out of scope)

## Current Documentation

See parent directory for active documentation:
- `refactoring_sessions.md` - Current focused implementation plan
- `EXPERT-REVIEW-PROMPT.md` - Architecture review guidelines

## Note on External Dependencies

The `external/zen_websocket` symlink remains but is unused. WebSocket support is explicitly out of scope for this REST-focused library.