using Pkg
using Conda

#Conda.pip_interop(true)
Conda.pip_interop(true, env=Conda.ROOTENV)
Conda.pip("install", "ds_store")

# Force Julia to use the Conda Python
ENV["PYTHON"] = ""
Pkg.build("PyCall")

# Print confirmation message
println("Python dependencies installed successfully via Conda!")
