# Robot model (private)

`mars_robot.gltf` and `mars_robot.bin` are the robot's CAD, and they are not in this public repository.
The release workflow copies them here from the private `LEEXR16/MARS_v3-archive` (`HMI/frontend/models/`)
using the `ARCHIVE_DEPLOY_KEY` secret. To build on the laptop, copy them from that folder first.
Without them, the app still works but its 3D view says the model failed to load (the 2D view is unaffected).
