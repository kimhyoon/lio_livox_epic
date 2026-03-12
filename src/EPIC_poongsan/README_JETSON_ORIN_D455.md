# EPIC Exploration Planner - Jetson Orin AGX + RealSense D455

This branch contains EPIC (Efficient Planning for Infrastructure-free Coverage) configured for **Jetson Orin AGX** with **Intel RealSense D455** camera, integrated with FAST-LIVO2 odometry system.

## Important Notes

⚠️ **This is NOT for I.MX8 board** - This branch is specifically configured for Jetson Orin AGX platform.

⚠️ **FAST-LIVO2 Integration** - This version integrates with [FAST-LIVO2](https://github.com/hku-mars/FAST-LIVO2) (custom repository) for LiDAR-Inertial-Visual odometry instead of the original simulation-based odometry.

## Hardware Requirements

- **Platform**: NVIDIA Jetson Orin AGX (64GB recommended)
- **Camera**: Intel RealSense D455
- **LiDAR**: Mid-360 LiDAR (for FAST-LIVO2)
- **IMU**: Built-in IMU in Mid-360 or external IMU

## Software Dependencies

- ROS Noetic
- OpenCV 4
- PCL (Point Cloud Library)
- Eigen3
- Intel RealSense SDK 2.0
- FAST-LIVO2 (custom repository)

## Key Differences from Original EPIC

### 1. Odometry Source
- **Original**: Simulation-based odometry (`/odom` topic)
- **This Version**: FAST-LIVO2 odometry (`/aft_mapped_to_odom` topic)

### 2. Point Cloud Source
- **Original**: Simulated depth sensor
- **This Version**: RealSense D455 depth camera via FAST-LIVO2 (`/cloud_registered` topic)

### 3. Frame Transformations
- Static transform bridge required between FAST-LIVO frame (`camera_init`) and camera frame (`camera_link`)
- Transform handled by `smart_static_tf_bridge.py` in FAST-LIVO2 workspace

### 4. Configuration Parameters
- Adjusted for real-world hardware (see `d455.yaml`)
- Optimized clustering parameters for scattered frontier detection
- Finer cell size (0.2m vs 0.4m in simulation)

## Critical Input Topic Requirements

### Required Topics from FAST-LIVO2:

1. **Odometry**: `/aft_mapped_to_odom` (nav_msgs/Odometry)
   - Published by FAST-LIVO2
   - Must be in `camera_init` frame

2. **Point Cloud**: `/cloud_registered` (sensor_msgs/PointCloud2)
   - Published by FAST-LIVO2
   - Registered point cloud in `camera_init` frame

3. **TF Transforms**:
   - `camera_init` → `aft_mapped` (from FAST-LIVO2)
   - `camera_link` → `camera_init` (from smart_static_tf_bridge.py)
   - Note: The static TF bridge node must stay alive to maintain the transform

### Message Synchronization:
- Uses `message_filters::sync_policies::ApproximateTime`
- Subscribes to both `/aft_mapped_to_odom` and `/cloud_registered`
- Default queue size: 100
- Synchronization slop: 0.1 seconds

## Installation

### 1. Clone FAST-LIVO2 (Custom Repository)
```bash
cd ~/
# Clone your custom FAST-LIVO2 repository
git clone <your-fast-livo2-repo-url> fast_livo2_ws/src/FAST-LIVO2
cd fast_livo2_ws
catkin build
```

### 2. Clone EPIC (This Repository)
```bash
cd ~/
mkdir -p epic_ws/src
cd epic_ws/src
git clone -b jetson-orin-agx https://github.com/sanghun17/EPIC_poongsan.git
cd ..
catkin build -DCMAKE_BUILD_TYPE=Release
```

## Configuration Files

### Main Configuration: `d455.yaml`
Located at: `src/EPIC/src/global_planner/exploration_manager/config/d455.yaml`

**Key Parameters**:
```yaml
# Frontier Detection
FrontierManager/cell_size: 0.2  # Finer than simulation (0.4)

# Clustering Parameters (Critical for real-world performance)
FrontierManager/cluster_min_radius: 2.0  # DBSCAN epsilon - max neighbor distance
FrontierManager/cluster_direction_radius: -0.5  # Normal similarity threshold
FrontierManager/cluster_minmum_point_num: 2  # Minimum points per cluster

# Observation Parameters
FrontierManager/good_observation_trust_length: 5.0
FrontierManager/frontier_observation_trust_length: 10.0
```

### Launch Files
1. **Real Hardware**: `d455.launch`

## Running the Demo

### Terminal 1: Start FAST-LIVO2
```bash
cd ~/fast_livo2_ws
source devel/setup.bash
roslaunch fast_livo fast_livo_d455.launch  # Use your FAST-LIVO2 launch file
```
### Terminal 2: Start EPIC Exploration
```bash
cd ~/epic_ws
source devel/setup.bash
roslaunch epic_planner d455.launch
```

### Terminal 4: Trigger Exploration (in RViz)
1. Open RViz
2. Set Fixed Frame to `camera_init`
3. Add visualization topics:
   - `/exploration_node/frt/markers` - Frontier markers
   - `global_tour` - Global Graph
4. Use RViz "2D Nav Goal" tool to trigger exploration
5. Or use command line:
```bash
# Trigger exploration programmatically
rostopic pub /move_base_simple/goal geometry_msgs/PoseStamped "header:
  frame_id: 'camera_init'
pose:
  position: {x: 5.0, y: 0.0, z: 0.0}
  orientation: {w: 1.0}"
```

## Troubleshooting

### Problem: "no odom" warnings continuously
**Cause**: Odometry not being received or point cloud is empty
**Solution**:
1. Verify FAST-LIVO2 is publishing: `rostopic list | grep aft_mapped`
2. Check TF tree: `rosrun tf view_frames`
3. Ensure `smart_static_tf_bridge.py` is running (stays alive with `rospy.spin()`)

### Problem: "no frontier" - exploration finishes immediately
**Cause**: Frontiers detected but clustering fails
**Solution**:
1. Check cluster parameters in `d455.yaml`
2. Increase `cluster_min_radius` (try 2.0 - 3.0)
3. Decrease `cluster_direction_radius` (try -0.5 to -1.0)
4. Verify frontiers are visible in RViz: `/exploration_node/frt/width`

### Problem: TF lookup errors
**Cause**: Static transform bridge exited prematurely
**Solution**:
1. Ensure FAST-LIVO2's `smart_static_tf_bridge.py` uses `rospy.spin()` not `rospy.sleep()`
2. Check node is running: `rosnode list | grep tf_bridge`

### Problem: Point cloud is empty after filtering
**Cause**: Voxel filter too aggressive or frame transformation issues
**Solution**:
1. Check original cloud has points: `rostopic echo /cloud_registered -n 1`
2. Adjust voxel grid leaf size in `sim_lio.cpp` (default: 0.1m)

## Code Changes from Original EPIC

### 1. Odometry Integration (`sim_lio.cpp`)
- Changed from simulated odometry to FAST-LIVO2 odometry subscription
- Added message synchronization for `/aft_mapped_to_odom` and `/cloud_registered`
- Implemented frame transformation support with `T_body_to_cloud_` matrix
- **Optimization**: Voxel filtering before transformation (process fewer points)
- **Bug Fix**: Properly populate `ld_->lidar_cloud_` member variable

### 2. Frontier Clustering (`frontier_manager.cpp`)
- Relaxed clustering parameters for real-world scattered frontiers
- Added NaN detection and handling in normal vector processing
- **Bug Fix**: Skip NaN normals instead of crashing

### 3. Configuration (`d455.yaml`)
- Cell size: 0.4 → 0.2 (finer resolution)
- cluster_min_radius: 0.1 → 2.0 (allow distant points to cluster)
- cluster_direction_radius: 0.15 → -0.5 (allow different normal orientations)
- cluster_minmum_point_num: 3 → 2 (fewer points needed per cluster)


## Repository Structure

```
EPIC_poongsan/
├── src/EPIC/src/
│   ├── global_planner/
│   │   ├── exploration_manager/
│   │   │   ├── config/d455.yaml          # Main config
│   │   │   └── launch/d455.launch        # Launch file
│   │   ├── frontier_manager/             # Frontier detection & clustering
│   │   ├── lidar_map/                    # Point cloud processing & odometry
│   │   └── pointcloud_topo/              # Topological graph
│   └── local_planner/                    # MINCO trajectory planner
└── README_JETSON_ORIN_D455.md           # This file
```

## Known Issues

1. **First run may take time**: Initial map building requires FAST-LIVO2 to converge
2. **Clustering sensitive to environment**: Sparse environments may need parameter tuning
3. **Frame transformation overhead**: Real-time transformation adds ~2-5ms per cloud

## Credits

- **Original EPIC**: [HKU-MARS EPIC](https://github.com/hku-mars/EPIC)
- **FAST-LIVO2**: [HKU-MARS FAST-LIVO2](https://github.com/hku-mars/FAST-LIVO2)
- **This Integration**: Configured for Jetson Orin AGX with RealSense D455

## Contact

For issues specific to this Jetson Orin + D455 integration, please open an issue on this repository's `jetson-orin-agx` branch.

## License

Same as original EPIC project.
