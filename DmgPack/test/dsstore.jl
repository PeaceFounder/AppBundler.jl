import DmgPack
using DmgPack.DSStore
using Test
using TOML
#dsstore_dict = TOML.parsefile(joinpath(dirname(@__DIR__), "recipes/dmg/DS_Store.toml"))


dsstore_dict = DmgPack.construct_dsstore_dict(; bundle_name = "MyApp.app")

fname = joinpath(tempdir(), "DS_Store")
rm(fname, force=true)

dst = DSStore.open_dsstore(fname, "w+")

for file_key in keys(dsstore_dict)
    file_dict = dsstore_dict[file_key]
    for entry_key in keys(file_dict)
        dst[file_key, entry_key] = file_dict[entry_key]
    end
end

dsstore_dict["MyApp.app"]["Iloc"] = tuple(dsstore_dict["MyApp.app"]["Iloc"]...)
dsstore_dict["Applications"]["Iloc"] = tuple(dsstore_dict["Applications"]["Iloc"]...)

@test dsstore_dict == convert(Dict, dst) 
