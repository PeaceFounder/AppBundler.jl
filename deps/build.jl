using Pkg
using Conda

Conda.add("ds_store", channel="conda-forge")

# Force Julia to use the Conda Python
ENV["PYTHON"] = ""
Pkg.build("PyCall")

# Print confirmation message
println("Python dependencies installed successfully via Conda!")
