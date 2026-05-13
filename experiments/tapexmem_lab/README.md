# Tape × Memory Lab

This lab explores the product-space VM idea in Moonlift.

Current file:

- `machine.mlua` — current experiment: state is carried through typed block parameters, with separate invariant, exec, GC, and dispatch regions.
- `DESIGN.md` — notes for the current experiment.

The point is to explore how a VM step can preserve both:

- a tape/fact projection, and
- a concrete memory/state projection.
