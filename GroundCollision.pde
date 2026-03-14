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
 * Simple physics system where everything is a sphere (ball) or plane (wall) to simplify collision detection
 */

final float UNIT = 0.1f;       // 1 voxel = 0.1 world units
final float EPS  = 0.0001f; // what is EPS ?

Ball player;

PVector gravity = new PVector(0, u(0.25f), 0);   // +Y is downward

// Wider and longer terrain strip
int cols = 48;
int rows = 96;

// World dimensions 
float worldW = u(4000);   
float worldH = u(1500); 
float worldD = u(4000);  

float cellW;
float cellD;

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

  player = new Ball(u(120), u(180), u(120), u(14));  // 14 voxels radius = 1.4 world units
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

void resetCameraImmediate() {
  PVector flatForward = player.getFlatForward();
  PVector desiredEye = PVector.sub(player.position, PVector.mult(flatForward, u(110)));
  desiredEye.add(0, -u(55), 0);

  PVector desiredTarget = PVector.add(player.position, PVector.mult(flatForward, u(24)));
  desiredTarget.add(0, -u(10), 0);

  camEye.set(desiredEye);
  camTarget.set(desiredTarget);
}

void setFollowCamera() {
  PVector flatForward = player.getFlatForward();

  PVector desiredEye = PVector.sub(player.position, PVector.mult(flatForward, u(110)));
  desiredEye.add(0, -u(55), 0);

  // keep camera above terrain a bit
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
    camEye.x, camEye.y, camEye.z, /* cam pos */
    camTarget.x, camTarget.y, camTarget.z, /* eye target pos */
    0, 1, 0 /* up */
    );

  perspective(PI/3.0, width/height, 0.1, 10000);
}

void generateTerrain() {
  heights = new float[cols][rows];
  cells   = new GroundCell[cols - 1][rows - 1];

  noiseDetail(4, 0.52f);

  float normScale_A = 0.075f;
  float normScale_B = 0.028f;

  // calculate random height map based terrain
  for (int indexWidth = 0; indexWidth < cols; ++indexWidth) {
    for (int indexDepth = 0; indexDepth < rows; ++indexDepth) {
      float normalWidth_A = indexWidth * normScale_A;
      float normalDepth_A = indexDepth * normScale_A;

      float normalWidth_B = indexWidth * normScale_B + 200.0f;
      float normalDepth_B = indexDepth * normScale_B + 600.0f;

      float broad = noise(normalWidth_A, normalDepth_A);
      float large = noise(normalWidth_B, normalDepth_B);

      float height_A = map(broad, 0, 1, worldH * 0.50f, worldH * 0.82f);
      float height_B = map(large, 0, 1, -u(22), u(22));

      float heightAdjusted = height_A + height_B;
      heights[indexWidth][indexDepth] = snapToVoxel(heightAdjusted);
    }
  }

  // generate the actual grid
  for (int indexWidth = 0; indexWidth < cols - 1; ++indexWidth) {
    for (int indexDepth = 0; indexDepth < rows - 1; ++indexDepth) {
      float baseGrey;
      if ((indexWidth + indexDepth) % 2 == 0) baseGrey = random(88, 125);
      else                  baseGrey = random(132, 176);

      cells[indexWidth][indexDepth] = new GroundCell(indexWidth, indexDepth, baseGrey);
    }
  }
}

// used to ...
void clearCollisionFlags() {
  for (int indexWidth = 0; indexWidth < cols - 1; ++indexWidth) {
    for (int indexDepth = 0; indexDepth < rows - 1; ++indexDepth) {
      cells[indexWidth][indexDepth].colliding = false;
    }
  }
}

// used to ...
void drawTerrain() {
  for (int indexWidth = 0; indexWidth < cols - 1; ++indexWidth) {
    for (int indexDepth = 0; indexDepth < rows - 1; ++indexDepth) {
      cells[indexWidth][indexDepth].display();
    }
  }
}

float terrainHeightAt(float x_, float z_) {
  x_ = constrain(x_, 0, worldW - EPS);
  z_ = constrain(z_, 0, worldD - EPS);

  int indexWidth = constrain(floor(x_ / cellW), 0, cols - 2);
  int indexDepth = constrain(floor(z_ / cellD), 0, rows - 2);

  float x0 = indexWidth * cellW;
  float z0 = indexDepth * cellD;

  float uCoord = (x_ - x0) / cellW;
  float vCoord = (z_ - z0) / cellD;

  float h00 = heights[indexWidth][indexDepth];
  float h10 = heights[indexWidth + 1][indexDepth];
  float h01 = heights[indexWidth][indexDepth + 1];
  float h11 = heights[indexWidth + 1][indexDepth + 1];

  float h0 = lerp(h00, h10, uCoord);
  float h1 = lerp(h01, h11, uCoord);
  return lerp(h0, h1, vCoord);
}

PVector terrainNormalAt(float x_, float z_) {
  float epsX = max(u(4), cellW * 0.30f);
  float epsZ = max(u(4), cellD * 0.30f);

  float xL = max(0, x_ - epsX);
  float xR = min(worldW, x_ + epsX);
  float zD = max(0, z_ - epsZ);
  float zU = min(worldD, z_ + epsZ);

  float hL = terrainHeightAt(xL, z_);
  float hR = terrainHeightAt(xR, z_);
  float hD = terrainHeightAt(x_, zD);
  float hU = terrainHeightAt(x_, zU);

  PVector tx = new PVector(xR - xL, hR - hL, 0);
  PVector tz = new PVector(0, hU - hD, zU - zD);

  PVector n = tx.cross(tz);
  n.normalize();

  // upward in Processing 3D means negative Y
  if (n.y > 0) n.mult(-1);

  return n;
}

PVector projectOntoPlane(PVector v, PVector n) {
  return PVector.sub(v, PVector.mult(n, v.dot(n)));
}

float u(float voxels) {
  return voxels * UNIT;
}

float snapToVoxel(float v) {
  return round(v / UNIT) * UNIT;
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

  GroundCell(int i_, int j_, float baseGrey_) {
    indexWidth = i_;
    indexDepth = j_;
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

    // softer orange tint instead of hard red replacement
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
  float engineAccel      = u(0.38f);
  float brakeAccel       = u(0.52f);
  float airAccel         = u(0.08f);

  float maxForwardSpeed  = u(7.0f);
  float maxReverseSpeed  = u(3.0f);
  float maxPlanarSpeed   = u(6.6f);

  float lateralGrip      = 0.12f;   // higher = tighter / less slide
  float driveDrag        = 0.012f;
  float coastDrag        = 0.035f;
  float airDrag          = 0.006f;

  float steerRate        = 0.030f;
  float jumpSpeed        = u(4.4f);

  float groundSnapDist   = u(1.2f);
  float groundDetachSpeed = u(2.0f); // if moving away from ground faster than this, don't snap

  Ball(float x_, float y_, float z_, float radius_) {
    position = new PVector(snapToVoxel(x_), snapToVoxel(y_), snapToVoxel(z_));
    velocity = new PVector();
    groundNormal = new PVector(0, -1, 0);
    radius = radius_;
  }

  void placeOnGround() {
    float gy = terrainHeightAt(position.x, position.z);
    position.y = gy - radius;
    grounded = true;
    groundNormal.set(terrainNormalAt(position.x, position.z));
  }

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

  void consumeJump() {
    if (jumpQueued && grounded) {
      velocity.add(PVector.mult(groundNormal, jumpSpeed));
      position.add(PVector.mult(groundNormal, u(2)));
      grounded = false;
    }
    jumpQueued = false;
  }

  void applyGroundDrive(float throttle, float steer) {
    PVector grndNorm = groundNormal.copy();

    PVector velocityNormal = PVector.mult(grndNorm, velocity.dot(grndNorm));
    PVector velocityTangent = PVector.sub(velocity, velocityNormal);

    PVector forward = getForwardOnPlane(grndNorm);
    PVector right = grndNorm.cross(forward);
    if (right.magSq() < 0.000001f) right = new PVector(0, 0, 1);
    else right.normalize();

    float forwardSpeed = velocityTangent.dot(forward);
    float sideSpeed = velocityTangent.dot(right);

    float steerFactor = 0.25f + 0.75f * min(abs(forwardSpeed) / maxForwardSpeed, 1.0f);
    yaw += steer * steerRate * steerFactor;

    // recalc after yaw changes
    forward = getForwardOnPlane(grndNorm);
    right = grndNorm.cross(forward);
    if (right.magSq() < 0.000001f) right = new PVector(0, 0, 1);
    else right.normalize();

    forwardSpeed = velocityTangent.dot(forward);
    sideSpeed = velocityTangent.dot(right);

    if (throttle > 0) {
      velocityTangent.add(PVector.mult(forward, engineAccel * throttle));
    } else if (throttle < 0) {
      velocityTangent.add(PVector.mult(forward, brakeAccel * throttle));
    }

    // kill sideways slide without killing all tangential motion
    velocityTangent.add(PVector.mult(right, -sideSpeed * lateralGrip));

    // drag
    if (abs(throttle) < 0.001f) velocityTangent.mult(1.0f - coastDrag);
    else                        velocityTangent.mult(1.0f - driveDrag);

    // clamp forward / reverse speed
    forwardSpeed = velocityTangent.dot(forward);
    float clampedForward = constrain(forwardSpeed, -maxReverseSpeed, maxForwardSpeed);
    velocityTangent.add(PVector.mult(forward, clampedForward - forwardSpeed));

    // extra safety clamp on total planar speed
    if (velocityTangent.mag() > maxPlanarSpeed) {
      velocityTangent.normalize().mult(maxPlanarSpeed);
    }

    velocity.set(PVector.add(velocityTangent, velocityNormal));
  }

  void applyAirControl(float throttle, float steer) {
    PVector forward = getFlatForward();

    if (abs(throttle) > 0.001f) {
      velocity.add(PVector.mult(forward, throttle * airAccel));
    }

    yaw += steer * steerRate * 0.35f;
    velocity.mult(1.0f - airDrag);
  }

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

  void solveTerrainCollision() {
    grounded = false;

    float groundY = terrainHeightAt(position.x, position.z);
    PVector terrainNormal = terrainNormalAt(position.x, position.z);

    float verticalCorrection = (position.y + radius) - groundY; // >0 = penetrating, <0 = hovering
    float velocityNormal = velocity.dot(terrainNormal);                            // relative to upward normal

    boolean canSnap =
      verticalCorrection >= -groundSnapDist &&
      velocityNormal < groundDetachSpeed;

    if (canSnap) {
      float correctionDist = verticalCorrection / max(0.15f, -terrainNormal.y);
      position.add(PVector.mult(terrainNormal, correctionDist));

      // remove only velocity into the surface
      velocityNormal = velocity.dot(terrainNormal);
      if (velocityNormal < 0) {
        velocity.sub(PVector.mult(terrainNormal, velocityNormal));
      }

      grounded = true;
      groundNormal.set(terrainNormal);
      markCollidingCell(position.x, position.z);
    } else {
      groundNormal.set(0, -1, 0);
    }
  }

  PVector getFlatForward() {
    PVector forward = new PVector(cos(yaw), 0, sin(yaw));
    if (forward.magSq() < 0.000001f) forward.set(1, 0, 0);
    else forward.normalize();
    return forward;
  }

  PVector getForwardOnPlane(PVector n) {
    PVector forward = new PVector(cos(yaw), 0, sin(yaw));
    forward = projectOntoPlane(forward, n);
    if (forward.magSq() < 0.000001f) forward = new PVector(1, 0, 0);
    else forward.normalize();
    return forward;
  }

  float getPlanarSpeed() {
    PVector normal = grounded ? groundNormal : new PVector(0, -1, 0);
    PVector velocityTangent = PVector.sub(velocity, PVector.mult(normal, velocity.dot(normal)));
    return velocityTangent.mag();
  }

  void bump() {
    PVector normal = grounded ? groundNormal.copy() : new PVector(0, -1, 0);
    velocity.add(PVector.mult(normal, u(3.8f)));

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

    // directional nose so heading reads like a tiny player
    pushMatrix();
    rotateY(yaw);
    translate(radius * 0.82f, 0, 0);
    fill(245, 190, 120);
    box(radius * 0.9f, radius * 0.25f, radius * 0.38f);
    popMatrix();

    // top marker
    pushMatrix();
    translate(0, -radius * 0.65f, 0);
    fill(90, 90, 95);
    box(radius * 0.65f, radius * 0.16f, radius * 0.65f);
    popMatrix();

    popMatrix();
  }

  /*
  * Helper Debug Visual function to highlight cells 
  */
  void markCollidingCell(float x_, float z_) {
    // translate position into grid indices
    int xCellAxisIndex = constrain(floor(x_ / cellW), 0, cols - 2); // width
    int zCellAxisIndex = constrain(floor(z_ / cellD), 0, rows - 2); // depth

    // enable collision indication bool - changes colour of ground cell currently
    cells[xCellAxisIndex][zCellAxisIndex].colliding = true;

    // adjaceny check  - flag neighbors too 
    if (xCellAxisIndex > 0)         cells[xCellAxisIndex - 1][zCellAxisIndex].colliding = true;
    if (xCellAxisIndex < cols - 2)  cells[xCellAxisIndex + 1][zCellAxisIndex].colliding = true;
    if (zCellAxisIndex > 0)         cells[xCellAxisIndex][zCellAxisIndex - 1].colliding = true;
    if (zCellAxisIndex < rows - 2)  cells[xCellAxisIndex][zCellAxisIndex + 1].colliding = true;
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
