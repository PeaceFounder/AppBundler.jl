using AppBundler.DSStore
using Test
using TOML

dsstore_dict = TOML.parsefile(joinpath(dirname(@__DIR__), "recipes/dmg/DS_Store.toml"))

fname = joinpath(tempdir(), "DS_Store")
rm(fname, force=true)

dst = DSStore.open_dsstore(fname, "w+")

dsstore_dict["."]["icvl"] = ("type", "icnv")
dsstore_dict["."]["vSrn"] = ("long", 1)

for file_key in keys(dsstore_dict)
    file_dict = dsstore_dict[file_key]
    for entry_key in keys(file_dict)
        dst[file_key, entry_key] = file_dict[entry_key]
    end
end

dsstore_dict["{{APP_NAME}}.app"]["Iloc"] = tuple(dsstore_dict["{{APP_NAME}}.app"]["Iloc"]...)
dsstore_dict["Applications"]["Iloc"] = tuple(dsstore_dict["Applications"]["Iloc"]...)

@test dsstore_dict == convert(Dict, dst) 


