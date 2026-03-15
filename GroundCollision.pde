/**
 * Balls and walls prototype - if it's not a sphere, it's a plane
 *
 * Notes:
 * - grounded support removes only into-ground velocity
 * - movement is acceleration-based
 * - arcade "car" feel using heading + throttle + lateral grip
 * - follow camera
 * - all world sizes are authored around a 0.1 voxel unit
 *
 * Coordinate note for Processing P3D:
 * - +Y goes downward
 * - smaller Y = higher up
 *
 * Balls & Walls:
 * Simple physics system where everything is a sphere (ball) or plane (wall)
 * so collision stays cheap and easy to reason about.
 */

final float UNIT = 0.1f;     // 1 voxel = 0.1 world units
final float EPS  = 0.0001f;  // tiny offset used when sampling near edges so we do not hit the last cell boundary exactly

Ball player;

PVector gravity = new PVector(0, u(0.25f), 0);   // +Y is downward in Processing P3D

// Terrain grid resolution
int cols = 48;
int rows = 96;

// World dimensions
float worldW = u(4000);
float worldH = u(1500);
float worldD = u(4000);

// Cached terrain cell size
float cellW;
float cellD;

// Heightmap data + render cells
float[][] heights;
GroundCell[][] cells;

// Camera
PVector camEye    = new PVector();
PVector camTarget = new PVector();

// Input
boolean wDown = false;
boolean aDown = false;
boolean sDown = false;
boolean dDown = false;
boolean jumpQueued = false;

void setup() {
  size(600, 600, P3D);
  noSmooth();

  cellW = worldW / (cols - 1.0f);
  cellD = worldD / (rows - 1.0f);

  generateTerrain();

  // spawn above terrain, then snap down onto the support surface
  player = new Ball(u(120), u(180), u(120), u(14));
  player.placeOnGround();

  resetCameraImmediate();
}

void draw() {
  background(10);

  clearCollisionFlags();
  player.update();

  setFollowCamera();
  setupSceneLighting();

  drawTerrain();
  player.display();

  drawHUD();
}

void setupSceneLighting() {
  ambientLight(70, 70, 70);
  directionalLight(200, 200, 200, -0.35f, 0.65f, -0.25f);
  directionalLight(110, 100, 95, 0.45f, 0.2f, 0.35f);
}

/*
 * Hard snap camera into place on startup so it does not ease in from origin.
 */
void resetCameraImmediate() {
  PVector flatForward = player.getFlatForward();

  PVector desiredEye = PVector.sub(player.position, PVector.mult(flatForward, u(110)));
  desiredEye.add(0, -u(55), 0);

  PVector desiredTarget = PVector.add(player.position, PVector.mult(flatForward, u(24)));
  desiredTarget.add(0, -u(10), 0);

  camEye.set(desiredEye);
  camTarget.set(desiredTarget);
}

/*
 * Follow camera:
 * - sits behind the current heading
 * - looks slightly ahead of the player
 * - gets lifted if terrain would clip into it
 * - eases toward the desired position for smoother motion
 */
void setFollowCamera() {
  PVector flatForward = player.getFlatForward();

  PVector desiredEye = PVector.sub(player.position, PVector.mult(flatForward, u(110)));
  desiredEye.add(0, -u(55), 0);

  // sample terrain under the desired eye point and keep the camera above it
  float sampleX = constrain(desiredEye.x, 0, worldW - EPS);
  float sampleZ = constrain(desiredEye.z, 0, worldD - EPS);
  float camGroundY = terrainHeightAt(sampleX, sampleZ);
  float minCameraY = camGroundY - u(36); // smaller Y = higher
  if (desiredEye.y > minCameraY) desiredEye.y = minCameraY;

  PVector desiredTarget = PVector.add(player.position, PVector.mult(flatForward, u(24)));
  desiredTarget.add(0, -u(10), 0);

  camEye.lerp(desiredEye, 0.12f);
  camTarget.lerp(desiredTarget, 0.18f);

  camera(
    camEye.x, camEye.y, camEye.z,       /* camera position */
    camTarget.x, camTarget.y, camTarget.z, /* look target */
    0, 1, 0                             /* up vector */
  );

  perspective(PI / 3.0f, (float) width / (float) height, 0.1f, 10000.0f);
}

/*
 * Create a height map terrain using 2 noise layers:
 * - one for broad rolling shape
 * - one for larger offset variation
 *
 * Final heights are snapped to the voxel grid so terrain values stay clean.
 */
void generateTerrain() {
  heights = new float[cols][rows];
  cells   = new GroundCell[cols - 1][rows - 1];

  noiseDetail(4, 0.52f);

  float mediumNoiseScale = 0.075f;
  float largeNoiseScale  = 0.028f;

  // calculate heightmap values first
  for (int indexWidth = 0; indexWidth < cols; ++indexWidth) {
    for (int indexDepth = 0; indexDepth < rows; ++indexDepth) {
      float mediumNoiseWidth = indexWidth * mediumNoiseScale;
      float mediumNoiseDepth = indexDepth * mediumNoiseScale;

      float largeNoiseWidth = indexWidth * largeNoiseScale + 200.0f;
      float largeNoiseDepth = indexDepth * largeNoiseScale + 600.0f;

      float broadNoise = noise(mediumNoiseWidth, mediumNoiseDepth);
      float largeNoise = noise(largeNoiseWidth, largeNoiseDepth);

      float baseHeight = map(broadNoise, 0, 1, worldH * 0.50f, worldH * 0.82f);
      float heightOffset = map(largeNoise, 0, 1, -u(22), u(22));

      float heightAdjusted = baseHeight + heightOffset;
      heights[indexWidth][indexDepth] = snapToVoxel(heightAdjusted);
    }
  }

  // build the visible terrain cells from the heightmap
  for (int indexWidth = 0; indexWidth < cols - 1; ++indexWidth) {
    for (int indexDepth = 0; indexDepth < rows - 1; ++indexDepth) {
      float baseGrey;

      if ((indexWidth + indexDepth) % 2 == 0) baseGrey = random(88, 125);
      else                                    baseGrey = random(132, 176);

      cells[indexWidth][indexDepth] = new GroundCell(indexWidth, indexDepth, baseGrey);
    }
  }
}

/*
 * Collision tint is recalculated every frame.
 * Clear all touched cell flags first, then let the current frame's contact solve mark them again.
 */
void clearCollisionFlags() {
  for (int indexWidth = 0; indexWidth < cols - 1; ++indexWidth) {
    for (int indexDepth = 0; indexDepth < rows - 1; ++indexDepth) {
      cells[indexWidth][indexDepth].colliding = false;
    }
  }
}

void drawTerrain() {
  for (int indexWidth = 0; indexWidth < cols - 1; ++indexWidth) {
    for (int indexDepth = 0; indexDepth < rows - 1; ++indexDepth) {
      cells[indexWidth][indexDepth].display();
    }
  }
}

/*
 * Sample the terrain height at any X/Z world position using bilinear interpolation.
 * This makes terrain support smooth even though the heightmap is stored on a grid.
 */
float terrainHeightAt(float worldX, float worldZ) {
  worldX = constrain(worldX, 0, worldW - EPS);
  worldZ = constrain(worldZ, 0, worldD - EPS);

  int indexWidth = constrain(floor(worldX / cellW), 0, cols - 2);
  int indexDepth = constrain(floor(worldZ / cellD), 0, rows - 2);

  float x0 = indexWidth * cellW;
  float z0 = indexDepth * cellD;

  float uCoord = (worldX - x0) / cellW;
  float vCoord = (worldZ - z0) / cellD;

  float h00 = heights[indexWidth][indexDepth];
  float h10 = heights[indexWidth + 1][indexDepth];
  float h01 = heights[indexWidth][indexDepth + 1];
  float h11 = heights[indexWidth + 1][indexDepth + 1];

  float h0 = lerp(h00, h10, uCoord);
  float h1 = lerp(h01, h11, uCoord);

  return lerp(h0, h1, vCoord);
}

/*
 * Estimate the terrain normal by sampling nearby heights in X and Z.
 * The cross product gives the slope direction, then we flip it if needed so it points upward.
 */
PVector terrainNormalAt(float worldX, float worldZ) {
  float sampleOffsetX = max(u(4), cellW * 0.30f);
  float sampleOffsetZ = max(u(4), cellD * 0.30f);

  float xL = max(0, worldX - sampleOffsetX);
  float xR = min(worldW, worldX + sampleOffsetX);
  float zD = max(0, worldZ - sampleOffsetZ);
  float zU = min(worldD, worldZ + sampleOffsetZ);

  float hL = terrainHeightAt(xL, worldZ);
  float hR = terrainHeightAt(xR, worldZ);
  float hD = terrainHeightAt(worldX, zD);
  float hU = terrainHeightAt(worldX, zU);

  PVector tangentX = new PVector(xR - xL, hR - hL, 0);
  PVector tangentZ = new PVector(0, hU - hD, zU - zD);

  PVector normal = tangentX.cross(tangentZ);
  normal.normalize();

  // upward in Processing P3D means negative Y
  if (normal.y > 0) normal.mult(-1);

  return normal;
}

/*
 * Remove the part of vector v that points along normal n.
 * Result is the piece of motion that lies along the plane.
 */
PVector projectOntoPlane(PVector v, PVector n) {
  return PVector.sub(v, PVector.mult(n, v.dot(n)));
}

float u(float voxels) {
  return voxels * UNIT;
}

/*
 * Snap authored/static values onto the 0.1 unit grid.
 * Avoid doing this to live dynamic motion every frame or the movement gets jittery.
 */
float snapToVoxel(float value) {
  return round(value / UNIT) * UNIT;
}

void drawHUD() {
  hint(DISABLE_DEPTH_TEST);
  camera();
  noLights();

  fill(255);
  textAlign(LEFT, TOP);
  text(
    "FPS: " + nf(frameRate, 1, 3) +
    "\nspeed: " + nf(player.getPlanarSpeed(), 1, 3) +
    "\nyaw: " + nf(degrees(player.yaw), 1, 2) +
    "\ngrounded: " + player.grounded +
    "\nW/S throttle  A/D steer  SPACE jump  click bump",
    12, 12
  );

  hint(ENABLE_DEPTH_TEST);
}

class GroundCell {
  int indexWidth, indexDepth;
  float baseGrey;
  boolean colliding = false;

  GroundCell(int indexWidth_, int indexDepth_, float baseGrey_) {
    indexWidth = indexWidth_;
    indexDepth = indexDepth_;
    baseGrey = baseGrey_;
  }

  void display() {
    float x0 = indexWidth * cellW;
    float x1 = (indexWidth + 1) * cellW;
    float z0 = indexDepth * cellD;
    float z1 = (indexDepth + 1) * cellD;

    float h00 = heights[indexWidth][indexDepth];
    float h10 = heights[indexWidth + 1][indexDepth];
    float h11 = heights[indexWidth + 1][indexDepth + 1];
    float h01 = heights[indexWidth][indexDepth + 1];

    pushStyle();
    noStroke();

    color topBase   = color(baseGrey);
    color frontBase = color(max(0, baseGrey - 16));
    color leftBase  = color(max(0, baseGrey - 30));

    // softer orange collision tint instead of a harsh full-red swap
    float topMix   = colliding ? 0.34f : 0.0f;
    float frontMix = colliding ? 0.28f : 0.0f;
    float leftMix  = colliding ? 0.24f : 0.0f;

    color topHit   = color(232, 142, 78);
    color frontHit = color(212, 122, 62);
    color leftHit  = color(186, 102, 50);

    fill(lerpColor(topBase, topHit, topMix));
    beginShape(QUADS);
    vertex(x0, h00, z0);
    vertex(x1, h10, z0);
    vertex(x1, h11, z1);
    vertex(x0, h01, z1);
    endShape();

    fill(lerpColor(frontBase, frontHit, frontMix));
    beginShape(QUADS);
    vertex(x0, h00, z0);
    vertex(x1, h10, z0);
    vertex(x1, worldH, z0);
    vertex(x0, worldH, z0);
    endShape();

    fill(lerpColor(leftBase, leftHit, leftMix));
    beginShape(QUADS);
    vertex(x0, h00, z0);
    vertex(x0, h01, z1);
    vertex(x0, worldH, z1);
    vertex(x0, worldH, z0);
    endShape();

    popStyle();
  }
}

class Ball {
  PVector position;
  PVector velocity;
  PVector groundNormal;

  float radius;
  float yaw = 0;

  boolean grounded = false;

  // --- tuning ---
  float engineAccel = u(0.38f);
  float brakeAccel  = u(0.52f);
  float airAccel    = u(0.08f);

  float maxForwardSpeed = u(7.0f);
  float maxReverseSpeed = u(3.0f);
  float maxPlanarSpeed  = u(6.6f);

  float lateralGrip = 0.12f;   // higher = tighter / less sideways drift
  float driveDrag   = 0.012f;
  float coastDrag   = 0.035f;
  float airDrag     = 0.006f;

  float steerRate = 0.030f;
  float jumpSpeed = u(4.4f);

  float groundSnapDist     = u(1.2f);
  float groundDetachSpeed  = u(2.0f); // if moving away from the ground too quickly, stop snapping to it

  Ball(float x_, float y_, float z_, float radius_) {
    position = new PVector(snapToVoxel(x_), snapToVoxel(y_), snapToVoxel(z_));
    velocity = new PVector();
    groundNormal = new PVector(0, -1, 0);
    radius = radius_;
  }

  /*
   * Spawn/reset helper.
   * Find support height below the sphere and place it so the bottom just touches the ground.
   */
  void placeOnGround() {
    float groundY = terrainHeightAt(position.x, position.z);
    position.y = groundY - radius;
    grounded = true;
    groundNormal.set(terrainNormalAt(position.x, position.z));
  }

  /*
   * Main update order:
   * 1. consume jump input
   * 2. build simple throttle + steer input
   * 3. apply ground or air movement
   * 4. integrate gravity
   * 5. move position
   * 6. solve world bounds
   * 7. solve terrain support
   */
  void update() {
    consumeJump();

    float throttle = 0;
    float steer = 0;

    if (wDown) throttle += 1;
    if (sDown) throttle -= 1;
    if (aDown) steer -= 1;
    if (dDown) steer += 1;

    if (grounded) {
      applyGroundDrive(throttle, steer);
    } else {
      applyAirControl(throttle, steer);
    }

    velocity.add(gravity);
    position.add(velocity);

    solveBounds();
    solveTerrainCollision();
  }

  /*
   * Jump pushes along the current ground normal instead of straight world-up.
   * That makes jumps behave better on slopes.
   */
  void consumeJump() {
    if (jumpQueued && grounded) {
      velocity.add(PVector.mult(groundNormal, jumpSpeed));
      position.add(PVector.mult(groundNormal, u(2))); // small extra push so we leave the support cleanly
      grounded = false;
    }

    jumpQueued = false;
  }

  /*
   * Ground movement model:
   * - split velocity into normal and tangent pieces
   * - tangent = motion along the ground plane
   * - normal = motion into / away from the ground
   *
   * We only steer and accelerate the tangent part.
   * The normal part is preserved separately so support physics stays stable.
   */
  void applyGroundDrive(float throttle, float steer) {
    PVector supportNormal = groundNormal.copy();

    // velocityNormal = motion pointing into / out of the support normal
    PVector velocityNormal = PVector.mult(supportNormal, velocity.dot(supportNormal));

    // velocityTangent = motion sliding along the support plane
    PVector velocityTangent = PVector.sub(velocity, velocityNormal);

    // forward is current heading projected onto the support plane
    PVector forward = getForwardOnPlane(supportNormal);

    // right gives us sideways motion relative to heading
    PVector right = supportNormal.cross(forward);
    if (right.magSq() < 0.000001f) right = new PVector(0, 0, 1);
    else right.normalize();

    float forwardSpeed = velocityTangent.dot(forward);
    float sideSpeed = velocityTangent.dot(right);

    // steering gets stronger as forward motion increases
    float steerFactor = 0.25f + 0.75f * min(abs(forwardSpeed) / maxForwardSpeed, 1.0f);
    yaw += steer * steerRate * steerFactor;

    // recalc basis after yaw changed
    forward = getForwardOnPlane(supportNormal);
    right = supportNormal.cross(forward);
    if (right.magSq() < 0.000001f) right = new PVector(0, 0, 1);
    else right.normalize();

    forwardSpeed = velocityTangent.dot(forward);
    sideSpeed = velocityTangent.dot(right);

    // apply forward/back acceleration along the support plane
    if (throttle > 0) {
      velocityTangent.add(PVector.mult(forward, engineAccel * throttle));
    } else if (throttle < 0) {
      velocityTangent.add(PVector.mult(forward, brakeAccel * throttle));
    }

    // kill some sideways drift without zeroing out all tangent motion
    velocityTangent.add(PVector.mult(right, -sideSpeed * lateralGrip));

    // use stronger drag when not actively driving
    if (abs(throttle) < 0.001f) velocityTangent.mult(1.0f - coastDrag);
    else                        velocityTangent.mult(1.0f - driveDrag);

    // clamp speed along the current forward axis
    forwardSpeed = velocityTangent.dot(forward);
    float clampedForward = constrain(forwardSpeed, -maxReverseSpeed, maxForwardSpeed);
    velocityTangent.add(PVector.mult(forward, clampedForward - forwardSpeed));

    // safety clamp on total tangent speed
    if (velocityTangent.mag() > maxPlanarSpeed) {
      velocityTangent.normalize().mult(maxPlanarSpeed);
    }

    // rebuild final velocity from tangent + normal components
    velocity.set(PVector.add(velocityTangent, velocityNormal));
  }

  /*
   * Air movement is weaker:
   * - throttle still nudges forward/back along current heading
   * - steer still rotates heading a bit
   * - light drag stops air motion from growing forever
   */
  void applyAirControl(float throttle, float steer) {
    PVector forward = getFlatForward();

    if (abs(throttle) > 0.001f) {
      velocity.add(PVector.mult(forward, throttle * airAccel));
    }

    yaw += steer * steerRate * 0.35f;
    velocity.mult(1.0f - airDrag);
  }

  /*
   * Clamp the sphere inside the prototype world.
   * When blocked by a boundary, zero the velocity on that axis instead of bouncing.
   */
  void solveBounds() {
    if (position.x < radius) {
      position.x = radius;
      if (velocity.x < 0) velocity.x = 0;
    } else if (position.x > worldW - radius) {
      position.x = worldW - radius;
      if (velocity.x > 0) velocity.x = 0;
    }

    if (position.z < radius) {
      position.z = radius;
      if (velocity.z < 0) velocity.z = 0;
    } else if (position.z > worldD - radius) {
      position.z = worldD - radius;
      if (velocity.z > 0) velocity.z = 0;
    }

    if (position.y < radius) {
      position.y = radius;
      if (velocity.y < 0) velocity.y = 0;
    }

    // fail-safe reset if something goes badly wrong
    if (position.y > worldH + u(180)) {
      position.set(u(120), u(160), u(120));
      velocity.set(0, 0, 0);
      yaw = 0;
      placeOnGround();
    }
  }

  /*
   * Terrain support solve:
   * - sample ground height + normal under the sphere
   * - if close enough, snap the sphere onto the support surface
   * - remove only the part of velocity moving into the surface normal
   * - keep tangent motion so the sphere can continue to travel across the slope
   *
   * This is the main thing stopping floaty bounce behavior.
   */
  void solveTerrainCollision() {
    grounded = false;

    float groundY = terrainHeightAt(position.x, position.z);
    PVector terrainNormal = terrainNormalAt(position.x, position.z);

    // > 0 means the bottom of the sphere is inside the terrain
    // < 0 means the sphere is hovering above the terrain
    float supportPenetrationOrGap = (position.y + radius) - groundY;

    // velocity projected onto terrain normal tells us how much we are moving into/out of the surface
    float velocityAlongTerrainNormal = velocity.dot(terrainNormal);

    boolean canSnap =
      supportPenetrationOrGap >= -groundSnapDist &&
      velocityAlongTerrainNormal < groundDetachSpeed;

    if (canSnap) {
      // convert vertical penetration/gap into movement along the support normal
      float correctionDist = supportPenetrationOrGap / max(0.15f, -terrainNormal.y);
      position.add(PVector.mult(terrainNormal, correctionDist));

      // remove only inward normal velocity; do not touch tangent velocity
      velocityAlongTerrainNormal = velocity.dot(terrainNormal);
      if (velocityAlongTerrainNormal < 0) {
        velocity.sub(PVector.mult(terrainNormal, velocityAlongTerrainNormal));
      }

      grounded = true;
      groundNormal.set(terrainNormal);
      markCollidingCell(position.x, position.z);
    } else {
      groundNormal.set(0, -1, 0);
    }
  }

  /*
   * Flat heading direction used for camera and air control.
   */
  PVector getFlatForward() {
    PVector forward = new PVector(cos(yaw), 0, sin(yaw));

    if (forward.magSq() < 0.000001f) forward.set(1, 0, 0);
    else forward.normalize();

    return forward;
  }

  /*
   * Heading direction projected onto the current support plane.
   * This makes forward motion follow the slope instead of fighting it.
   */
  PVector getForwardOnPlane(PVector supportNormal) {
    PVector forward = new PVector(cos(yaw), 0, sin(yaw));
    forward = projectOntoPlane(forward, supportNormal);

    if (forward.magSq() < 0.000001f) forward = new PVector(1, 0, 0);
    else forward.normalize();

    return forward;
  }

  /*
   * Planar speed = velocity with the normal component removed.
   * Useful for HUD/debug because it measures actual travel across the surface.
   */
  float getPlanarSpeed() {
    PVector supportNormal = grounded ? groundNormal : new PVector(0, -1, 0);
    PVector velocityTangent = PVector.sub(velocity, PVector.mult(supportNormal, velocity.dot(supportNormal)));

    return velocityTangent.mag();
  }

  /*
   * Small debug impulse:
   * - pushes away from the support normal
   * - adds a little random sideways motion
   */
  void bump() {
    PVector supportNormal = grounded ? groundNormal.copy() : new PVector(0, -1, 0);
    velocity.add(PVector.mult(supportNormal, u(3.8f)));

    PVector side = new PVector(random(-1, 1), 0, random(-1, 1));
    if (side.magSq() > 0.000001f) side.normalize();
    velocity.add(PVector.mult(side, u(1.5f)));
  }

  void display() {
    pushMatrix();
    translate(position.x, position.y, position.z);

    noStroke();

    // main body sphere
    fill(210);
    sphereDetail(18);
    sphere(radius);

    // small forward marker so heading is easy to read
    pushMatrix();
    rotateY(yaw);
    translate(radius * 0.82f, 0, 0);
    fill(245, 190, 120);
    box(radius * 0.9f, radius * 0.25f, radius * 0.38f);
    popMatrix();

    // top marker makes the silhouette easier to read
    pushMatrix();
    translate(0, -radius * 0.65f, 0);
    fill(90, 90, 95);
    box(radius * 0.65f, radius * 0.16f, radius * 0.65f);
    popMatrix();

    popMatrix();
  }

  /*
   * Helper debug visual:
   * mark the touched terrain cell plus direct neighbors so the contact patch reads better.
   */
  void markCollidingCell(float x_, float z_) {
    int xCellAxisIndex = constrain(floor(x_ / cellW), 0, cols - 2);
    int zCellAxisIndex = constrain(floor(z_ / cellD), 0, rows - 2);

    cells[xCellAxisIndex][zCellAxisIndex].colliding = true;

    if (xCellAxisIndex > 0)        cells[xCellAxisIndex - 1][zCellAxisIndex].colliding = true;
    if (xCellAxisIndex < cols - 2) cells[xCellAxisIndex + 1][zCellAxisIndex].colliding = true;
    if (zCellAxisIndex > 0)        cells[xCellAxisIndex][zCellAxisIndex - 1].colliding = true;
    if (zCellAxisIndex < rows - 2) cells[xCellAxisIndex][zCellAxisIndex + 1].colliding = true;
  }
}

void mousePressed() {
  player.bump();
}

void keyPressed() {
  if (key == 'w' || key == 'W') wDown = true;
  if (key == 'a' || key == 'A') aDown = true;
  if (key == 's' || key == 'S') sDown = true;
  if (key == 'd' || key == 'D') dDown = true;

  if (key == ' ') jumpQueued = true;
}

void keyReleased() {
  if (key == 'w' || key == 'W') wDown = false;
  if (key == 'a' || key == 'A') aDown = false;
  if (key == 's' || key == 'S') sDown = false;
  if (key == 'd' || key == 'D') dDown = false;
}
