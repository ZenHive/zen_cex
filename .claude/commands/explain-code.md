# Code Explanation Helper

You are helping to explain Phoenix and LiveView code following the template's patterns and conventions.

The code to explain is about: $ARGUMENTS.

## Instructions

1. **Analyze Code Structure**:
   - Identify the type of code (context, controller, LiveView, schema, etc.)
   - Explain the purpose and responsibility of each module
   - Show how it fits into the overall application architecture

2. **Explain Phoenix Patterns**:
   - Context pattern for business logic
   - Controller pattern for HTTP requests
   - LiveView pattern for real-time UI
   - Schema pattern for data validation
   - Component pattern for reusable UI

3. **Break Down Complex Code**:
   - Explain function purpose and parameters
   - Show data flow through the application
   - Highlight important business logic
   - Explain error handling patterns

4. **Template-Specific Patterns**:

### **Authentication Flow**
```elixir
# Explain how user authentication works
defmodule BlockwatchWeb.UserAuth do
  # This module handles user authentication for both
  # regular HTTP requests and LiveView connections

  def log_in_user(conn, user, params \\ %{}) do
    # Creates a session token and stores it in the session
    # The remember_me option creates a persistent token
  end
end
```

### **Context Pattern**
```elixir
# Explain how contexts encapsulate business logic
defmodule Blockwatch.Accounts do
  # This context module provides the public API
  # for all user account operations

  def get_user!(id) do
    # Fetches user by ID, raises if not found
    # Used when you expect the user to exist
  end

  def create_user(attrs) do
    # Creates a new user with validation
    # Returns {:ok, user} or {:error, changeset}
  end
end
```

### **LiveView Pattern**
```elixir
# Explain LiveView lifecycle and state management
defmodule BlockwatchWeb.UserLive.Registration do
  use BlockwatchWeb, :live_view

  def mount(_params, _session, socket) do
    # Initialize the LiveView state
    # Set up assigns and prepare changeset
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    # Handle form validation in real-time
    # Update changeset without saving
  end
end
```

### **Schema Pattern**
```elixir
# Explain data validation and relationships
defmodule Blockwatch.Accounts.User do
  use Ecto.Schema

  def changeset(user, attrs) do
    # Validates and transforms user data
    # Enforces business rules and constraints
    user
    |> cast(attrs, [:email, :password])
    |> validate_email()
    |> validate_password()
  end
end
```

5. **Explain Key Concepts**:

### **Assigns in LiveView**
- State management between server and client
- How assigns trigger re-renders
- Temporary assigns for performance

### **PubSub for Real-Time Updates**
- Broadcasting changes to connected clients
- Subscribing to topic-based updates
- Handling messages in LiveView

### **Error Handling Patterns**
- Using `{:ok, result}` and `{:error, reason}` tuples
- Pattern matching for different outcomes
- Graceful error recovery

### **Security Considerations**
- Input validation and sanitization
- Authentication and authorization
- CSRF protection
- SQL injection prevention

6. **Performance Implications**:
   - Database query optimization
   - LiveView process lifecycle
   - Memory usage considerations
   - Asset loading and caching

7. **Testing Strategies**:
   - Unit tests for contexts
   - Integration tests for controllers
   - LiveView testing patterns
   - Factory usage for test data

## Example Usage

Paste the code you want explained, and I'll provide:
- Overall purpose and architecture
- Line-by-line explanation of complex parts
- How it fits into Phoenix conventions
- Security and performance considerations
- Testing recommendations
- Common patterns and anti-patterns
- Refactoring suggestions

I'll tailor explanations to your experience level and focus on the most important concepts for understanding the Delta Watch Phoenix application.
