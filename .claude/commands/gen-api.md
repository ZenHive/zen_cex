# Generate Phoenix API

You are helping to generate a Phoenix API following the template's conventions and patterns.

The user wants an API for $ARGUMENTS. Ask for more clarity if not enough is provided.

## Instructions

1. **Analyze existing API patterns**:
   - Check `lib/block_watch_web/router.ex` for existing API pipeline
   - Look at `lib/block_watch_web/controllers/` for controller patterns
   - Review `lib/block_watch_web/controllers/error_json.ex` for error handling
   - Check authentication patterns in `lib/block_watch_web/user_auth.ex`

2. **Generate API with proper structure**:
   - Controller module in `lib/block_watch_web/controllers/api/`
   - JSON view module in `lib/block_watch_web/controllers/api/`
   - Test file in `test/block_watch_web/controllers/api/`
   - Route configuration in `router.ex` under `:api` pipeline

3. **Follow template conventions**:
   - Use `BlockwatchWeb, :controller` for controllers
   - Use `BlockwatchWeb, :view` for JSON views
   - Return proper HTTP status codes
   - Include comprehensive error handling
   - Use existing context functions for business logic

4. **Include these controller actions**:
   - `index/2` - List resources (GET /api/resources)
   - `show/2` - Get specific resource (GET /api/resources/:id)
   - `create/2` - Create new resource (POST /api/resources)
   - `update/2` - Update resource (PUT/PATCH /api/resources/:id)
   - `delete/2` - Delete resource (DELETE /api/resources/:id)

5. **Authentication patterns**:
   - Use API token authentication for stateless requests
   - Implement rate limiting for API endpoints
   - Include proper CORS configuration if needed
   - Use `current_user` from authentication pipeline

6. **JSON response patterns**:
   ```elixir
   # Success responses
   render(conn, :show, resource: resource)
   render(conn, :index, resources: resources)

   # Error responses
   conn
   |> put_status(:unprocessable_entity)
   |> put_view(BlockwatchWeb.ErrorJSON)
   |> render(:"422")
   ```

7. **Input validation**:
   - Use changeset validations from context
   - Return validation errors in JSON format
   - Include field-specific error messages
   - Handle malformed JSON requests

8. **Testing pattern**:
   - Use `Phoenix.ConnTest` for API testing
   - Test all CRUD operations
   - Include authentication scenarios
   - Test error conditions and edge cases
   - Use factory data for consistent tests

## Example Usage

Ask the user:
- What resource/context is the API for? (e.g., "Users", "Products", "Orders")
- What operations are needed? (full CRUD or subset)
- What authentication level is required?
- What fields should be included in JSON responses?
- Are there any special business rules or validations?

Then generate the complete API following the template's patterns with proper authentication, validation, and error handling.
