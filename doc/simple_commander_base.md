# `simple_commander_base` Module

## Overview

The `simple_commander_base` module defines an abstract base class named `commander_base`. This class serves as a foundational template for all specific commander implementations within the system. Its primary purpose is to establish a common interface that all derived commanders must adhere to, ensuring consistent execution patterns.

## Key Components

### `commander_base` (Abstract Type)

This is the core abstract type provided by the module.
- It is declared as `abstract`, meaning it cannot be instantiated directly and must be extended by concrete commander classes.
- It contains the following procedures:
    - `execute`: A deferred subroutine (interface `generic_execute`) that must be implemented by subclasses. This procedure is intended to contain the specific logic for a given command.
    - `execute_safe`: A regular subroutine that provides a wrapper around the `execute` call to manage global state safely.

### `generic_execute` (Deferred Subroutine Interface)

- **Signature:** `subroutine generic_execute(self, cline)`
  - `self`: `class(commander_base), intent(inout)` - The commander object itself.
  - `cline`: `class(cmdline), intent(inout)` - The command line arguments object.
- **Purpose:** This deferred subroutine defines the standard interface for executing a commander. Concrete implementations of `commander_base` must provide an `execute` procedure that matches this interface. This is where the primary operational logic of a specific commander resides.

### `execute_safe` (Subroutine)

- **Signature:** `subroutine execute_safe(self, cline)`
  - `self`: `class(commander_base), intent(inout)` - The commander object.
  - `cline`: `class(cmdline), intent(inout)` - The command line arguments object.
- **Purpose:** This subroutine provides a controlled environment for executing a commander's `execute` method. It handles the setup and teardown of global objects, specifically:
    - It saves the current global `params_glob` (from `simple_parameters`) and `build_glob` (from `simple_builder`).
    - It nullifies these global objects before calling `self%execute(cline)`.
    - It restores the saved global objects after the execution finishes.
  This mechanism helps prevent unintended side effects and ensures a clean state for each commander's execution.

## Dependencies and Interactions

- **Base Class Role:** `simple_commander_base` is designed to be a parent class. Other modules will define concrete commanders that extend `commander_base` and implement the `generic_execute` procedure.
- **`simple_cmdline`:**
    - The `cmdline` type from this module is used as an argument in both `generic_execute` and `execute_safe` to pass command-line information.
- **`simple_parameters`:**
    - The `parameters` type and the global `params_glob` object from this module are used by `execute_safe` to manage application parameters during execution.
- **`simple_builder`:**
    - The `builder` type and the global `build_glob` object from this module are used by `execute_safe` to manage build configurations or states during execution.
- **`simple_lib.f08`:**
    - This file is included via an `include 'simple_lib.f08'` statement, suggesting it provides common definitions, constants, or utility functions used within the module.
