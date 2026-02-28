// ShieldInit.c — C constructor for dylib auto-initialization
// __attribute__((constructor)) chạy TỰ ĐỘNG khi dylib được load
// Gọi sang Swift function shield_constructor_entry() trong ShieldEntry.swift

extern void shield_constructor_entry(void);

__attribute__((constructor))
static void shield_dylib_init(void) {
    shield_constructor_entry();
}
