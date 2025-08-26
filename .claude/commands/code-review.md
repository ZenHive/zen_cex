# Elixir Library Code Review

You are helping to review Elixir library code following ZenCex conventions and best practices.

**IMPORTANT**: Refer to AGENTS.md for essential library guidelines including Elixir patterns, testing requirements, and architectural decisions.

The code you are reviewing is the current diff from HEAD in git.

Use git commands to figure out what the changes are.

## Instructions

1. **Review Code Against Library Standards**:
   - Check adherence to library design patterns
   - Verify proper module organization and naming
   - Ensure consistent error handling
   - Validate security best practices for API integrations

2. **Code Quality Checklist**:

### **Function Design**
- [ ] Functions are small and focused (under 20 lines when possible)
- [ ] Function names clearly describe their purpose
- [ ] Single responsibility principle is followed
- [ ] Functions are easily testable with clear inputs/outputs
- [ ] Public API is minimal (5-10 functions per module)

### **Code Organization**
- [ ] Proper separation of concerns (adapters, core, safety modules)
- [ ] Logical file structure following library conventions
- [ ] Related functions are grouped together
- [ ] Public and private functions are properly separated

### **Security**
- [ ] API keys are never hardcoded or logged
- [ ] Request signing is properly implemented
- [ ] Testnet vs production safety checks
- [ ] Rate limiting is respected
- [ ] Sensitive data is not exposed in errors

### **Performance**
- [ ] ETS operations use atomic functions
- [ ] Connection pooling configured appropriately
- [ ] No unnecessary GenServer overhead
- [ ] Efficient use of Req middleware pipeline
- [ ] Proper telemetry for monitoring

### **Error Handling**
- [ ] Consistent {:ok, result} / {:error, reason} tuples
- [ ] Raw errors passed without wrapping
- [ ] Appropriate use of `with` statements
- [ ] Graceful handling of API errors
- [ ] Clear error messages for debugging

### **Testing**
- [ ] Integration tests use real testnet APIs
- [ ] No mocks without testing real API first
- [ ] Actual API responses documented
- [ ] Both success and failure scenarios tested
- [ ] Testnet URLs enforced in tests

### **Documentation**
- [ ] All public functions have @spec annotations
- [ ] Complex functions have @doc strings with examples
- [ ] Module documentation explains purpose
- [ ] Code is self-documenting through good naming
- [ ] API behavior documented from real testing

### **Library Conventions**
- [ ] Adapter pattern properly implemented
- [ ] Req middleware used effectively
- [ ] ETS for stateless operations
- [ ] Endpoint registry pattern when applicable
- [ ] Clock synchronization for time-sensitive APIs

3. **ZenCex-Specific Patterns**:
   - Req-centric architecture (don't reimplement what Req provides)
   - ETS atomic operations for rate limiting
   - Endpoint discovery and runtime introspection
   - Multi-API support (spot, futures, margin)
   - Debug module for troubleshooting

4. **Provide Specific Feedback**:
   - Point out specific issues with line numbers
   - Suggest concrete improvements
   - Reference library patterns and examples
   - Prioritize security and reliability issues
   - Recommend refactoring opportunities

## Example Usage

Run git diff to see changes, and I'll analyze them against these standards and provide specific feedback on:
- Code quality and organization
- Security considerations
- Performance optimizations
- Library convention adherence
- Testing recommendations
- Integration best practices