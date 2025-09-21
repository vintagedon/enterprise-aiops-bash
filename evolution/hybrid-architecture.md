<!--
---
title: "Hybrid Architecture: Python-Bash Integration Patterns"
description: "Architectural patterns for integrating Python AI agent logic with Bash execution layer for complex automation workflows"
author: "VintageDon - https://github.com/vintagedon"
date: "2025-09-20"
version: "1.0"
status: "Conceptual"
tags:
- type: architecture-design
- domain: hybrid-systems
- tech: python-bash
- audience: architects
related_documents:
- "[Roadmap](roadmap.md)"
- "[Research Insights](research-insights.md)"
- "[Security Hardening Guide](../docs/security-hardening.md)"
---
-->

# **Hybrid Architecture: Python-Bash Integration Patterns**

This document explores architectural patterns for integrating Python-based AI agent logic with the Bash execution framework. The hybrid approach leverages each language's strengths while maintaining security and observability.

---

## **Architecture Rationale**

### Language-Specific Strengths

**Python: The "Brain"**

- Rich AI/ML libraries (scikit-learn, pytorch, transformers)
- Complex data structure manipulation and API integration
- Sophisticated error handling and control flow
- Agent framework ecosystems (CrewAI, AutoGen, LangChain)

**Bash: The "Hands"**

- Universal availability without runtime dependencies
- Predictable failure modes for agent decision-making
- Direct system interaction with minimal overhead
- Security patterns optimized for untrusted input

### Integration Challenges

**Current v1.0 Limitations:**

- Manual parameter passing between Python and Bash components
- No shared state management across language boundaries
- Error correlation requires manual log analysis
- Security context not preserved across execution boundaries

**Hybrid Architecture Goals:**

- Seamless state sharing between Python AI logic and Bash execution
- Unified error handling and observability across languages
- Security context propagation from Python to Bash
- Performance optimization for high-frequency operations

---

## **Proposed Integration Patterns**

### Pattern 1: Structured Message Passing

**Architecture Overview:**
Python AI agent communicates with Bash scripts through structured JSON messages, providing clear interfaces and validation boundaries.

```python
# Python agent side
import json
import subprocess
from typing import Dict, Any, List

class BashExecutor:
    def __init__(self, framework_path: str = "/opt/enterprise-automation"):
        self.framework_path = framework_path
        self.correlation_id = self._generate_correlation_id()
    
    def execute_operation(self, 
                         script_name: str, 
                         operation: str, 
                         parameters: Dict[str, Any],
                         security_context: Dict[str, str] = None) -> Dict[str, Any]:
        
        # Create execution message
        message = {
            "correlation_id": self.correlation_id,
            "script_name": script_name,
            "operation": operation,
            "parameters": parameters,
            "security_context": security_context or {},
            "timestamp": self._get_timestamp()
        }
        
        # Execute via message passing
        result = self._execute_with_message(message)
        
        # Parse and validate response
        return self._parse_execution_result(result)
    
    def _execute_with_message(self, message: Dict[str, Any]) -> str:
        script_path = f"{self.framework_path}/scripts/hybrid-executor.sh"
        
        process = subprocess.run(
            [script_path, "--message", json.dumps(message)],
            capture_output=True,
            text=True,
            timeout=300
        )
        
        if process.returncode != 0:
            raise ExecutionError(f"Script failed: {process.stderr}")
        
        return process.stdout
```

```bash
#!/usr/bin/env bash
# hybrid-executor.sh - Bash side of message passing

source "${SCRIPT_DIR}/framework/logging.sh"
source "${SCRIPT_DIR}/framework/security.sh"
source "${SCRIPT_DIR}/framework/validation.sh"

# Parse incoming message
parse_execution_message() {
    local message_json="$1"
    
    # Extract message components using jq
    CORRELATION_ID=$(echo "$message_json" | jq -r '.correlation_id')
    SCRIPT_NAME=$(echo "$message_json" | jq -r '.script_name')
    OPERATION=$(echo "$message_json" | jq -r '.operation')
    PARAMETERS=$(echo "$message_json" | jq -r '.parameters')
    SECURITY_CONTEXT=$(echo "$message_json" | jq -r '.security_context')
    
    # Validate message structure
    [[ -n "$CORRELATION_ID" ]] || die "Missing correlation_id in message"
    [[ -n "$SCRIPT_NAME" ]] || die "Missing script_name in message"
    [[ -n "$OPERATION" ]] || die "Missing operation in message"
    
    # Set correlation context for logging
    export CORRELATION_ID
}

# Execute operation with validation
execute_hybrid_operation() {
    log_info "Executing hybrid operation: $OPERATION for script: $SCRIPT_NAME"
    
    # Validate script exists and is executable
    local script_path="${SCRIPT_DIR}/operations/${SCRIPT_NAME}.sh"
    [[ -f "$script_path" && -x "$script_path" ]] || die "Script not found or not executable: $script_path"
    
    # Validate operation is allowed
    validate_operation_allowed "$SCRIPT_NAME" "$OPERATION"
    
    # Execute with parameters
    "$script_path" --operation "$OPERATION" --parameters "$PARAMETERS" --context "$SECURITY_CONTEXT"
}

# Return structured result
generate_execution_result() {
    local exit_code="$1"
    local output="$2"
    local error_output="$3"
    
    jq -n \
        --arg cid "$CORRELATION_ID" \
        --arg ts "$(date -u +%FT%TZ)" \
        --arg code "$exit_code" \
        --arg out "$output" \
        --arg err "$error_output" \
        '{
            correlation_id: $cid,
            timestamp: $ts,
            exit_code: ($code | tonumber),
            output: $out,
            error: $err,
            success: (($code | tonumber) == 0)
        }'
}
```

### Pattern 2: Shared State Management

**Architecture Overview:**
Temporary state storage enables complex workflows where Python AI logic and Bash execution need to share data across multiple operations.

```python
# Python state management
import tempfile
import json
import os
from contextlib import contextmanager

class SharedStateManager:
    def __init__(self):
        self.state_dir = tempfile.mkdtemp(prefix="aiops_state_")
        self.state_file = os.path.join(self.state_dir, "shared_state.json")
        self._initialize_state()
    
    def _initialize_state(self):
        initial_state = {
            "workflow_id": self._generate_workflow_id(),
            "created_at": self._get_timestamp(),
            "variables": {},
            "operation_history": []
        }
        self._write_state(initial_state)
    
    def set_variable(self, key: str, value: Any):
        state = self._read_state()
        state["variables"][key] = value
        state["updated_at"] = self._get_timestamp()
        self._write_state(state)
    
    def get_variable(self, key: str, default: Any = None) -> Any:
        state = self._read_state()
        return state["variables"].get(key, default)
    
    def record_operation(self, operation: str, result: Dict[str, Any]):
        state = self._read_state()
        state["operation_history"].append({
            "operation": operation,
            "timestamp": self._get_timestamp(),
            "result": result
        })
        self._write_state(state)
    
    @contextmanager
    def bash_context(self):
        """Context manager that exposes state to bash scripts"""
        try:
            # Set environment variable for bash access
            os.environ["SHARED_STATE_FILE"] = self.state_file
            yield self
        finally:
            # Cleanup
            if "SHARED_STATE_FILE" in os.environ:
                del os.environ["SHARED_STATE_FILE"]
```

```bash
#!/usr/bin/env bash
# Bash state management functions

# Read variable from shared state
get_shared_variable() {
    local key="$1"
    local default="${2:-null}"
    
    [[ -n "$SHARED_STATE_FILE" ]] || die "Shared state not available"
    [[ -f "$SHARED_STATE_FILE" ]] || die "Shared state file not found"
    
    jq -r --arg key "$key" --arg default "$default" \
        '.variables[$key] // $default' "$SHARED_STATE_FILE"
}

# Set variable in shared state
set_shared_variable() {
    local key="$1"
    local value="$2"
    
    [[ -n "$SHARED_STATE_FILE" ]] || die "Shared state not available"
    [[ -f "$SHARED_STATE_FILE" ]] || die "Shared state file not found"
    
    local temp_file
    temp_file=$(mktemp)
    
    jq --arg key "$key" --arg value "$value" --arg ts "$(date -u +%FT%TZ)" \
        '.variables[$key] = $value | .updated_at = $ts' \
        "$SHARED_STATE_FILE" > "$temp_file" && mv "$temp_file" "$SHARED_STATE_FILE"
}

# Record operation result
record_operation_result() {
    local operation="$1"
    local exit_code="$2"
    local output="$3"
    
    [[ -n "$SHARED_STATE_FILE" ]] || return 0
    
    local temp_file
    temp_file=$(mktemp)
    
    jq --arg op "$operation" \
       --arg ts "$(date -u +%FT%TZ)" \
       --arg code "$exit_code" \
       --arg out "$output" \
       '.operation_history += [{
           operation: $op,
           timestamp: $ts,
           exit_code: ($code | tonumber),
           output: $out
       }]' "$SHARED_STATE_FILE" > "$temp_file" && mv "$temp_file" "$SHARED_STATE_FILE"
}
```

### Pattern 3: Streaming Communication

**Architecture Overview:**
For long-running operations, streaming communication allows real-time monitoring and intervention by Python agents.

```python
# Python streaming communication
import asyncio
import json
from asyncio.subprocess import PIPE

class StreamingExecutor:
    async def execute_streaming(self, 
                               script_path: str, 
                               parameters: Dict[str, Any],
                               progress_callback=None) -> AsyncIterator[Dict[str, Any]]:
        
        # Prepare command
        cmd = [script_path, "--streaming", "--parameters", json.dumps(parameters)]
        
        # Start process
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=PIPE,
            stderr=PIPE
        )
        
        try:
            async for line in self._read_lines(process.stdout):
                # Parse streaming output
                try:
                    event = json.loads(line)
                    
                    # Call progress callback if provided
                    if progress_callback:
                        await progress_callback(event)
                    
                    yield event
                    
                except json.JSONDecodeError:
                    # Handle non-JSON output
                    yield {"type": "output", "data": line}
            
            # Wait for completion
            await process.wait()
            
        finally:
            if process.returncode is None:
                process.terminate()
                await process.wait()
    
    async def _read_lines(self, stream):
        while True:
            line = await stream.readline()
            if not line:
                break
            yield line.decode().strip()
```

```bash
#!/usr/bin/env bash
# Bash streaming output functions

# Emit structured progress event
emit_progress() {
    local event_type="$1"
    local progress_pct="$2"
    local message="$3"
    
    jq -n \
        --arg type "$event_type" \
        --arg ts "$(date -u +%FT%TZ)" \
        --arg pct "$progress_pct" \
        --arg msg "$message" \
        '{
            type: $type,
            timestamp: $ts,
            progress_percent: ($pct | tonumber),
            message: $msg
        }'
}

# Example long-running operation with progress
perform_long_operation() {
    local total_steps=10
    local current_step=0
    
    emit_progress "started" 0 "Beginning operation"
    
    while [[ $current_step -lt $total_steps ]]; do
        # Simulate work
        sleep 2
        
        current_step=$((current_step + 1))
        local progress_pct=$((current_step * 100 / total_steps))
        
        emit_progress "progress" "$progress_pct" "Completed step $current_step of $total_steps"
    done
    
    emit_progress "completed" 100 "Operation finished successfully"
}
```

---

## **Security Considerations**

### Cross-Language Security Context

**Challenge:** Maintaining security context and validation across Python-Bash boundaries while preventing privilege escalation or context injection.

**Solution Pattern:**

```python
# Python security context
class SecurityContext:
    def __init__(self, user_id: str, allowed_operations: List[str], risk_level: str):
        self.user_id = user_id
        self.allowed_operations = allowed_operations
        self.risk_level = risk_level
        self.context_hash = self._generate_context_hash()
    
    def serialize_for_bash(self) -> str:
        """Create tamper-evident security context for bash"""
        context_data = {
            "user_id": self.user_id,
            "allowed_operations": self.allowed_operations,
            "risk_level": self.risk_level,
            "timestamp": int(time.time()),
            "hash": self.context_hash
        }
        return base64.b64encode(json.dumps(context_data).encode()).decode()
```

```bash
# Bash security context validation
validate_security_context() {
    local context_b64="$1"
    
    # Decode and parse context
    local context_json
    context_json=$(echo "$context_b64" | base64 -d)
    
    # Extract and validate components
    local user_id operation_list risk_level timestamp context_hash
    user_id=$(echo "$context_json" | jq -r '.user_id')
    operation_list=$(echo "$context_json" | jq -r '.allowed_operations[]')
    risk_level=$(echo "$context_json" | jq -r '.risk_level')
    timestamp=$(echo "$context_json" | jq -r '.timestamp')
    context_hash=$(echo "$context_json" | jq -r '.hash')
    
    # Validate timestamp (prevent replay attacks)
    local current_time
    current_time=$(date +%s)
    if [[ $((current_time - timestamp)) -gt 300 ]]; then  # 5 minute window
        die "Security context expired"
    fi
    
    # Validate hash (prevent tampering)
    local expected_hash
    expected_hash=$(echo "${user_id}${operation_list}${risk_level}${timestamp}" | sha256sum | cut -d' ' -f1)
    [[ "$context_hash" == "$expected_hash" ]] || die "Security context tampered"
    
    # Set validated context for script use
    export VALIDATED_USER_ID="$user_id"
    export VALIDATED_RISK_LEVEL="$risk_level"
}
```

---

## **Performance Optimization**

### Execution Pool Pattern

**Challenge:** High-frequency AI agent operations create overhead from repeated process spawning and framework initialization.

**Solution:** Persistent execution pool with pre-initialized bash environments.

```python
# Python execution pool
import concurrent.futures
import queue
import subprocess
from typing import Dict, Any

class BashExecutionPool:
    def __init__(self, pool_size: int = 4):
        self.pool_size = pool_size
        self.available_executors = queue.Queue()
        self.busy_executors = set()
        self._initialize_pool()
    
    def _initialize_pool(self):
        """Pre-spawn bash executor processes"""
        for i in range(self.pool_size):
            executor = self._spawn_executor(f"pool_{i}")
            self.available_executors.put(executor)
    
    def _spawn_executor(self, executor_id: str) -> subprocess.Popen:
        """Spawn persistent bash executor process"""
        cmd = [
            "/opt/enterprise-automation/scripts/pool-executor.sh",
            "--pool-mode",
            "--executor-id", executor_id
        ]
        
        process = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        
        return process
    
    async def execute(self, operation: Dict[str, Any]) -> Dict[str, Any]:
        """Execute operation using pool"""
        # Get available executor
        executor = await self._get_executor()
        
        try:
            # Send operation
            operation_json = json.dumps(operation)
            executor.stdin.write(f"{operation_json}\n")
            executor.stdin.flush()
            
            # Read result
            result_line = executor.stdout.readline()
            result = json.loads(result_line)
            
            return result
            
        finally:
            # Return executor to pool
            self._return_executor(executor)
```

---

## **Implementation Timeline**

### Phase 1: Message Passing (Q2 2026)

- Structured JSON communication between Python and Bash
- Basic parameter validation and error propagation
- Correlation ID support for operation tracing

### Phase 2: State Management (Q3 2026)

- Shared state storage for complex workflows
- Operation history tracking
- State cleanup and garbage collection

### Phase 3: Advanced Patterns (Q4 2026)

- Streaming communication for long-running operations
- Execution pool optimization
- Advanced security context propagation

---

## **Migration Strategy**

### Backward Compatibility

- All hybrid patterns optional - existing v1.0 scripts continue to work
- Gradual adoption possible with framework feature flags
- Legacy integration patterns supported during transition

### Adoption Path

1. **Start Simple:** Message passing for new AI agent integrations
2. **Add Complexity:** State management for multi-step workflows
3. **Optimize Performance:** Execution pools for high-frequency operations
4. **Advanced Features:** Streaming and security patterns as needed

---

## **Documentation Metadata**

### Architecture Status

**Maturity:** Conceptual design based on v1.0 operational experience  
**Implementation:** Planned for v1.2+ framework releases  
**Validation:** Patterns tested in isolated development environments  

### Design Principles

**Language Separation:** Clear boundaries between Python AI logic and Bash execution  
**Security First:** All patterns designed with AI agent security threats in mind  
**Performance Aware:** Optimization patterns for enterprise-scale operations  

*Architecture Version: 1.0 | Last Updated: 2025-09-20 | Status: Conceptual*
