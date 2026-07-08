/-
  Sparkle Examples -- AXI5-Lite Verified Bus Interface

  Subordinate-side AXI5-Lite interface proven to refine the AXI protocol
  spec model extracted from ARM IHI 0022 Issue L.

  See:
    Sparkle/Verification/AXIProps.lean       -- spec-cited protocol theorems
    Sparkle/Verification/AXIRefinement.lean  -- spec ↔ RTL bisimulation
    docs/AXI_Spec_Map.md                     -- rule → theorem map
-/

import Examples.AXI.LiteSubordinate
