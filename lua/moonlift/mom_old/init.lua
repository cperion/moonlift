-- MOM initialization moved to modular build system.
--
-- This module path is deprecated. Use moonlift.mom.build.assemble instead:
--
--   local Assemble = require("moonlift.mom.build.assemble")
--   local artifact = Assemble.emit_object({name = "mom", module_name = "libmom_precompiled"})

error("moonlift.mom.init was removed in the precompiled MOM reorganization. Use moonlift.mom.build.assemble from the hosted build path.", 2)
