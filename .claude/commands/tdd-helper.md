# TDD Helper for Phoenix LiveView

You are helping to implement Test-Driven Development (TDD) for Phoenix LiveView applications following the template's patterns.

The user wants TDD for the following functionality: $ARGUMENTS. Ask for more clarity if not enough is provided.

## Instructions

1. **TDD Workflow**:
   - **Red**: Write failing test first
   - **Green**: Write minimal code to make test pass
   - **Refactor**: Improve code while keeping tests passing

2. **Test-First Approach**:
   - Start with business requirements
   - Write tests that describe expected behavior
   - Implement features to satisfy tests
   - Refactor with confidence

3. **LiveView TDD Patterns**:

### **Context Testing (Business Logic)**
```elixir
# Test business logic first
test "create_product/1 with valid data creates a product" do
  valid_attrs = %{name: "Test Product", price: 100}

  assert {:ok, %Product{} = product} = Catalog.create_product(valid_attrs)
  assert product.name == "Test Product"
  assert product.price == 100
end

test "create_product/1 with invalid data returns error changeset" do
  invalid_attrs = %{name: "", price: -1}

  assert {:error, %Ecto.Changeset{}} = Catalog.create_product(invalid_attrs)
end
```

### **LiveView Integration Testing**
```elixir
# Test LiveView interactions
test "displays product list", %{conn: conn} do
  product = insert(:product)

  {:ok, lv, _html} = live(conn, ~p"/products")

  assert has_element?(lv, "#product-#{product.id}")
  assert has_element?(lv, "[data-testid='product-name']", product.name)
end

test "creates product via form submission", %{conn: conn} do
  {:ok, lv, _html} = live(conn, ~p"/products/new")

  assert lv
    |> form("#product-form", product: %{name: "New Product", price: 50})
    |> render_submit()

  assert_redirect(lv, ~p"/products")
  assert Catalog.get_product_by_name("New Product")
end
```

### **Component Testing**
```elixir
# Test individual components
test "renders product card with all details" do
  product = build(:product, name: "Test Product", price: 100)

  html = render_component(&ProductCard.render/1, product: product)

  assert html =~ "Test Product"
  assert html =~ "$100"
  assert html =~ "data-testid=\"product-card\""
end
```

4. **TDD Best Practices**:

### **Start with High-Level Feature Tests**
- Write acceptance tests for user stories
- Test the complete user journey
- Use descriptive test names that explain business value

### **Work from Outside-In**
- Start with controller/LiveView tests
- Move to context tests
- End with individual function tests

### **Use Factories for Test Data**
- Create realistic test data with ExMachina
- Use build/insert strategically
- Keep tests isolated and independent

### **Test Behavior, Not Implementation**
- Focus on what the code should do
- Test public interfaces
- Avoid testing internal implementation details

5. **LiveView-Specific TDD Patterns**:

### **Event Handling**
```elixir
# Test event handling
test "clicking delete button removes product", %{conn: conn} do
  product = insert(:product)

  {:ok, lv, _html} = live(conn, ~p"/products")

  lv |> element("[data-testid='delete-product-#{product.id}']") |> render_click()

  refute has_element?(lv, "#product-#{product.id}")
  assert is_nil(Catalog.get_product(product.id))
end
```

### **Form Validation**
```elixir
# Test real-time validation
test "displays validation errors on invalid input", %{conn: conn} do
  {:ok, lv, _html} = live(conn, ~p"/products/new")

  lv
  |> form("#product-form", product: %{name: "", price: -1})
  |> render_change()

  assert has_element?(lv, "[data-testid='name-error']", "can't be blank")
  assert has_element?(lv, "[data-testid='price-error']", "must be greater than 0")
end
```

### **Authentication Testing**
```elixir
# Test authentication flows
test "redirects unauthenticated user to login", %{conn: conn} do
  {:error, {:redirect, %{to: "/users/log_in"}}} = live(conn, ~p"/dashboard")
end

test "authenticated user can access dashboard", %{conn: conn} do
  user = insert(:user)

  {:ok, lv, _html} =
    conn
    |> log_in_user(user)
    |> live(~p"/dashboard")

  assert has_element?(lv, "[data-testid='welcome']", "Welcome, #{user.email}")
end
```

6. **TDD Workflow Helper**:

### **Step 1: Write the Test**
- Describe the expected behavior
- Use clear, descriptive test names
- Set up necessary test data

### **Step 2: Run Tests (Red)**
- Ensure the test fails for the right reason
- Verify error messages are helpful

### **Step 3: Write Minimal Code (Green)**
- Implement just enough to make the test pass
- Don't over-engineer the solution

### **Step 4: Refactor**
- Improve code quality while keeping tests green
- Extract common patterns
- Follow Phoenix conventions

## Example Usage

Tell me:
- What feature are you implementing?
- What is the expected user behavior?
- What LiveView interactions are needed?
- What business rules should be enforced?

I'll help you write tests first, then implement the feature following TDD principles and the template's patterns.
