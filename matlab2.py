import meshlib.mrmeshpy as mm
import sys
import os

# load meshes
lumen = mm.loadMesh(lumenPath)

# Smoothing
relax_params = mm.MeshRelaxParams()
relax_params.iterations = 3
mm.relax(lumen, relax_params)

# Setup parameters
params = mm.OffsetParameters()
params.voxelSize = lumen.computeBoundingBox().diagonal() * 3e-3  # offset grid precision (algorithm is voxel based)
if mm.findRightBoundary(lumen.topology).empty():
    params.signDetectionMode = mm.SignDetectionMode.HoleWindingRule  # use if you have holes in mesh

# thickness (mm) 
wall_thick = 1.3

# Make offset mesh
offset1 = wall_thick

try:
    wall = mm.offsetMesh(lumen, offset1, params)
except ValueError as e:
    print(e)
    sys.exit(1)

base = os.path.splitext(os.path.basename(lumenPath))[0]

mm.saveMesh(lumen,  f"{base}_lumen.stl")
mm.saveMesh(wall, f"{base}_wall.stl")
