# TriState: Progress Report

## Out-of-Order Block Diagram

<p align="center"> <img src="OOO_architecture_tristate.png"/> <p
  align="center">Block Diagram</p> </p>

## Progress

### Checkpoint 1

- Intstruction Queue created with parameterized depth and width support
- Cacheline Adpater created from BMEM and cache interface
- Cache Arbiter created as a dummy block, separate Icache and Dcache to be created with priorty table tbd
- Line Buffer created that caches the hit cacheline and serves instruction on each cycle
- Module specific testbench for IQ and Cacheline adapter created and tested
- Line buffer behaviour validated with top_tb by passing assembly files and cross-checking commited instructions at ID stage through Verdi
- Block diagram created
- BMEM burst support yet to be fully leveraged
