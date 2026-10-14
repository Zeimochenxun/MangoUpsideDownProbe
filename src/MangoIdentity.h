#pragma once
// The one place that names the Mango build this suite is pinned to. Both the loader
// (Beta9Compatibility.m, string form) and the orientation/idle modules (Beta9Identity.h, byte
// form) read it. Refresh with: python -I tools/record_mango.py --mango-deb <deb> --version <v> --sha256 <h>
// then update the values below; tests/test_identity_table.py fails if they disagree with
// mango-compatibility.json. The UUIDs identify the unmodified Mango modules the suite was audited
// against; they are a compatibility check, not an authorization or signature check.
#define MS_MANGO_VERSION "1.0-Beta11-1"

#define MS_HELLO_UUID "A628D4E7-DB4D-3D51-BD0A-045CE96FF52F"
#define MS_PANDA_UUID "B61B7237-2F09-3D5C-99C2-5EBF6FD084B6"
#define MS_RENDERING_UUID "5D9C6F75-F810-3BE4-8980-7AC2A245C98F"

#define MS_HELLO_UUID_BYTES {0xa6,0x28,0xd4,0xe7,0xdb,0x4d,0x3d,0x51,0xbd,0x0a,0x04,0x5c,0xe9,0x6f,0xf5,0x2f}
#define MS_PANDA_UUID_BYTES {0xb6,0x1b,0x72,0x37,0x2f,0x09,0x3d,0x5c,0x99,0xc2,0x5e,0xbf,0x6f,0xd0,0x84,0xb6}

// AdaptiveColor 0.1.3 rewrites Mango's Metal source by exact string anchors. Beta10 changed that
// shader (flat/curved tint and glare anchors no longer occur), so on Beta11 the module would only
// fall back to Mango's original shader. 0 keeps it unloaded; set 1 only with an AdaptiveColor build
// whose anchors were re-audited against the pinned MangoOSRendering shader.
#define MS_ADAPTIVE_SUPPORTED 0
