#pragma once

// Tweak.m's fresh-init parameter path calls Pulse before its definition.
// Mark the forward declaration unused so the same forced include is harmless
// in TintMigration.m under -Wall -Wextra -Werror.
__attribute__((unused)) static void Pulse(void);
