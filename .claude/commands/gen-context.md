# Generate Phoenix Context

You are helping to generate a Phoenix context following the template's conventions and patterns.

The user wants a context for $ARGUMENTS. Ask for more clarity if not enough is provided.

## Instructions

1. **Analyze the existing codebase** to understand current patterns:
   - Look at `lib/block_watch/accounts.ex` for context pattern examples
   - Check `lib/block_watch/accounts/` for schema organization
   - Review existing tests in `test/block_watch/` for testing patterns

2. **Generate the context** with:
   - Main context module in `lib/block_watch/`
   - Schema module(s) in `lib/block_watch/[context_name]/`
   - Migration file(s) in `priv/repo/migrations/`
   - Test file in `test/block_watch/`
   - Factory definitions in `test/support/factory.ex`

3. **Follow template conventions**:
   - Use standard Ecto.Schema (integer primary keys by default)
   - Include proper associations and validations
   - Add `@doc` strings with examples for public functions
   - Use `changeset/2` pattern for validations
   - Include proper error handling with `{:ok, result}` or `{:error, changeset}`

4. **Include these functions in the context**:
   - `list_[resource]()` - List all resources
   - `get_[resource]!(id)` - Get resource by ID (raise on not found)
   - `get_[resource](id)` - Get resource by ID (return nil on not found)
   - `create_[resource](attrs)` - Create new resource
   - `update_[resource](resource, attrs)` - Update existing resource
   - `delete_[resource](resource)` - Delete resource
   - `change_[resource](resource, attrs \\ %{})` - Build changeset

5. **Testing pattern**:
   - Use ExMachina factories for test data
   - Test all public functions
   - Include both success and failure scenarios
   - Use descriptive test names

## Example Usage

Ask the user:
- What is the context name? (e.g., "Blog", "Products", "Orders")
- What are the main resources/schemas? (e.g., "Post", "Product", "Order")
- What fields should each schema have?
- What associations are needed?

Then generate the complete context following the template's patterns.
