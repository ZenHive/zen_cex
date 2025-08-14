# Generate Phoenix LiveView

You are helping to generate a Phoenix LiveView following the template's conventions and patterns.

The user wants an LiveView for $ARGUMENTS. Ask for more clarity if not enough is provided.

## Instructions

1. **Analyze existing LiveView patterns**:
   - Look at `lib/block_watch_web/live/` for existing LiveView structure
   - Check `lib/block_watch_web/live/user_live/` for authentication patterns
   - Review `lib/block_watch_web/components/core_components.ex` for available components
   - Check `lib/block_watch_web/user_auth.ex` for authentication helpers

2. **Generate LiveView with proper structure**:
   - LiveView module in `lib/block_watch_web/live/[context]_live/`
   - Template file `.html.heex` in the same directory
   - Test file in `test/block_watch_web/live/[context]_live/`
   - Route configuration in `router.ex`

3. **Follow template conventions**:
   - Use `BlockwatchWeb, :live_view` for the LiveView module
   - Include proper authentication with `on_mount` if needed
   - Use existing core components (`button`, `input`, `table`, etc.)
   - Follow DaisyUI classes for styling (`btn`, `input`, `select`, etc.)
   - Use Tailwind utilities for layout and responsive design

4. **Include these LiveView lifecycle functions**:
   - `mount/3` - Initialize assigns and handle authentication
   - `handle_event/3` - Handle user interactions
   - `handle_info/2` - Handle PubSub messages (if needed)
   - `render/1` - Template rendering (or separate .heex file)

5. **Authentication patterns**:
   - Use `on_mount: {BlockwatchWeb.UserAuth, :mount_current_user}` for optional auth
   - Use `on_mount: {BlockwatchWeb.UserAuth, :ensure_authenticated}` for required auth
   - Use `on_mount: {BlockwatchWeb.UserAuth, :redirect_if_user_is_authenticated}` for guest-only
   - Access current user with `socket.assigns.current_user`

6. **Form handling**:
   - Use `Phoenix.Component.to_form/2` for form creation
   - Handle form submission with `phx-submit` events
   - Use changesets for validation
   - Display errors with `core_components.error/1`

7. **Testing pattern**:
   - Use `Phoenix.LiveViewTest` for testing
   - Test mount, events, and navigation
   - Include both authenticated and unauthenticated scenarios
   - Use `live/2` helper for testing LiveView interactions

## Example Usage

Ask the user:
- What is the LiveView name and purpose? (e.g., "ProductList", "UserProfile", "Dashboard")
- What context/schema does it work with?
- What authentication level is needed?
- What user interactions are required? (forms, buttons, navigation)
- What data needs to be displayed?

Then generate the complete LiveView following the template's patterns with proper styling and functionality.
