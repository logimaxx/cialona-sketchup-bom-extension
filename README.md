# SketchUp BOM Export Extension – Cialona
## Overview

This project implements a custom SketchUp extension that extracts a Bill of Materials (BOM) according to Cialona’s specific production and costing rules.

The goal is not to generate a generic BOM, but a deterministic, reproducible output that matches how Cialona interprets SketchUp models for manufacturing, pricing, and downstream processing.

## Scope

The extension is responsible for:
- Reading geometry and metadata from SketchUp models
- Interpreting components, groups, layers, attributes, and naming conventions according to agreed rules
- Applying transformation and aggregation logic defined by Cialona
- Exporting a BOM in the agreed structure and format
- Anything outside these rules is explicitly out of scope unless documented and agreed upon.

## Key Principles

- **Specification-driven**. The current Cialona specification is the single source of truth.
- **No implicit assumptions.** Any ambiguous or missing rule must be clarified or explicitly documented as an assumption.
- **Deterministic output**. Same input model → same BOM output, every time.
- **Extensibility over hacks**. Logic is implemented in a way that allows future extensions without breaking existing behavior.

## Input Model Assumptions

The extension assumes that SketchUp models:
- Follow the agreed component / group structure
- Use naming conventions and attributes as specified
- Represent geometry in real-world units (as defined in the spec)

If a model violates these assumptions, results are undefined unless validation rules are added.

## Output

The generated BOM includes (subject to final specification):
- Identified parts / assemblies
- Quantities and dimensions
- Derived properties (e.g. surface, volume, material class)
- Export format: [to be finalized: CSV / JSON / XLSX / other]

Exact field names, ordering, and calculation rules are defined in the specification and test examples.

## Development Workflow

- All code is versioned in this repository
- Changes are tracked via commits and pull requests
- Specification changes must be reflected either in:
  - updated documentation, or
  - test cases demonstrating the new behavior

## Validation

Validation is done by:
- Comparing exported BOMs against real reference models
- Reviewing edge cases explicitly (nested components, mirrored geometry, custom objects, etc.)

If a case is not covered by tests or documentation, behavior should not be assumed.

## Non-Goals

This project does not aim to:
- Replace SketchUp modeling best practices
- Automatically “fix” invalid models
- Guess intent where data is missing
- Act as a general-purpose BOM exporter

Status

Current phase: Specification alignment & initial implementation
