# Phoenix Code Review

You are helping to review Phoenix code following the template's conventions and best practices.

The code you are reviewing is the current diff from HEAD in git.

Use git commands to figure out what the changes are.

## Instructions

1. **Review Code Against Template Standards**:
   - Check adherence to Phoenix conventions and patterns
   - Verify proper use of contexts, controllers, and LiveViews
   - Ensure consistent naming and organization
   - Validate security best practices

2. **Code Quality Checklist**:

### **Function Design**
- [ ] Functions are small and focused (under 20 lines when possible)
- [ ] Function names clearly describe their purpose
- [ ] Single responsibility principle is followed
- [ ] Functions are easily testable with clear inputs/outputs

### **Code Organization**
- [ ] Proper separation of concerns (business logic in contexts, presentation in views)
- [ ] Logical file structure following Phoenix conventions
- [ ] Related functions are grouped together
- [ ] Public and private functions are properly separated

### **Security**
- [ ] All user inputs are validated and sanitized
- [ ] Proper authentication and authorization checks
- [ ] CSRF protection enabled for forms
- [ ] SQL injection prevention (using Ecto queries)
- [ ] XSS prevention (proper escaping in templates)

### **Performance**
- [ ] No N+1 database queries (proper use of preloads)
- [ ] Database indexes for frequently queried fields
- [ ] Minimal assigns in LiveView
- [ ] Efficient database queries with proper selects

### **Error Handling**
- [ ] Proper pattern matching for error cases
- [ ] Consistent error return formats (`{:ok, result}` or `{:error, changeset}`)
- [ ] Appropriate use of `with` statements
- [ ] Graceful handling of edge cases

### **Testing**
- [ ] All public functions have tests
- [ ] Both success and failure scenarios tested
- [ ] Descriptive test names that explain intent
- [ ] Proper use of factories for test data
- [ ] LiveView interactions properly tested

### **Documentation**
- [ ] Complex functions have `@doc` strings with examples
- [ ] Code is self-documenting through good naming
- [ ] Comments only where absolutely necessary
- [ ] Module documentation explains purpose

### **Phoenix Conventions**
- [ ] Proper use of contexts for business logic
- [ ] Controllers are thin and delegate to contexts
- [ ] LiveViews follow proper lifecycle patterns
- [ ] Changesets used for all data validation
- [ ] Templates use semantic HTML with accessibility considerations

3. **Delta Watch-Specific Patterns**:
   - Using standard `Ecto.Schema` for all schemas
   - Following DaisyUI + Tailwind styling conventions
   - Proper authentication patterns with `UserAuth`
   - Using existing core components when possible
   - Following integer primary key conventions

4. **Provide Specific Feedback**:
   - Point out specific issues with line numbers
   - Suggest concrete improvements
   - Reference template patterns and examples
   - Prioritize security and performance issues
   - Recommend refactoring opportunities

## Example Usage

Paste the code you want reviewed, and I'll analyze it against these standards and provide specific feedback on:
- Code quality and organization
- Security considerations
- Performance optimizations
- Phoenix convention adherence
- Testing recommendations
- Refactoring suggestions
