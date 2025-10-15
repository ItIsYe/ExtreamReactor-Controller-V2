-- =========================================================
-- XReactor Node Debug Utility
-- Zeigt verfügbare Peripherals und deren Methoden an
-- =========================================================

print("=== XReactor Node Debug ===")

local sides = {"top","bottom","left","right","front","back"}

for _,side in ipairs(sides) do
    local p = peripheral.wrap(side)
    if p then
        print("\n["..side.."] "..(peripheral.getType(side) or "unknown"))
        local methods = peripheral.getMethods(side)
        if methods then
            for _,m in ipairs(methods) do
                print("  - "..m)
            end
        else
            print("  (keine Methoden gefunden)")
        end
    end
end

print("\nFertig. Drücke eine Taste zum Beenden.")
os.pullEvent("key")
