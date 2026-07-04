+++
title = "From Pixels to Tensors, Part 2: The 3D Graphics Pipeline"
author = ["Yi-Ping Pan (Cloudlet)"]
description = "From a single triangle to OpenGL and Vulkan — the linear algebra that turns geometry into pixels, and why the GPU pipeline is shaped the way it is."
date = 2026-06-26
draft = false
[taxonomies]
  tags = ["3d-rendering", "gpu", "opengl", "vulkan", "rasterization", "linear-algebra", "pixels-to-tensors"]
  categories = ["hardware-architecture"]
[extra]
  math = true
  toc = true
+++

[Part 1](@/technical/pixels-to-tensors/part-1-2d-rendering.md) describes how 2D graphics works. In summary, it can be reduced to two operations, rasterize and composite. Now I am curious about how 3D graphics works, and want to gradually work toward AI computation.

In the 2D world, the primitives that represent graphics are points, lines, and rectangles. However, when we move to 3D graphics, the primitives become points, lines, and **triangles**. The question the hardware must answer changes accordingly: given a triangle floating in a 3D world and a camera looking at it, which pixels on a flat screen does it cover, and what color is each one?

The answer is a sequence of coordinate transformations followed by a fill. Most of the work is linear algebra — matrix and vector arithmetic applied uniformly to every vertex — and the structure of that arithmetic is what the GPU was built to execute. We develop the pipeline one stage at a time, introducing each stage as the solution to a problem the previous stage leaves open.

The series runs: 2D rendering → 3D GPU pipeline → GPGPU → deep learning → MLIR.

> This series of articles represents my own attempt to understand the technical evolution from pixels to tensors. Each domain along this path—graphics, hardware architecture, compilers, and machine learning—is an extraordinarily deep field. I cannot claim to have fully mastered any of them. I am simply tracing this intellectual thread through first-principles reasoning and historical inquiry, documenting the process as I go. I hope these notes, however incomplete, may offer some value to fellow explorers navigating the same topics.


## The Triangle as the Primitive {#the-triangle-as-the-primitive}

Real-time 3D represents every object — a character, a vehicle, a terrain — as a collection of triangles.[^fn:1] Why is the triangle the basic unit of 3D graphics, rather than a square, a pentagon, or an arbitrary polygon? The choice is not aesthetic; it follows from three properties that no other polygon has at once.[^fn:2]

First, a triangle is always **planar**. Three points define exactly one plane; there is no way to place three points such that they fail to lie on a common flat surface. Four or more points carry no such guarantee. If a renderer is handed four "coplanar" corners and one of them drifts off the plane, the shape is no longer flat and its interior has no unambiguous filling. The triangle is therefore the only polygon that is flat by construction — every shape with more vertices may be bent out of its plane.

Second, a triangle is always **convex**. It has no interior dents. Filling a convex region is a decidable, branch-free test: a point lies inside the triangle if and only if it lies on the inner side of all three edges, a sign test the rasterizer can evaluate without branching.[^fn:3] Concave polygons must first be subdivided; triangles never require this.

Third, a triangle is **sufficient**. Any polygon decomposes into triangles, and any smooth surface is approximated by a sufficiently fine triangle mesh. The hardware therefore needs only one filling procedure, defined once for the triangle, and every other shape is built from it. This is the same economy the NES applied with its fixed 8×8 tile: define the unit precisely, then assemble everything from copies of it.

The simplest case is a _quad_ — a quadrilateral, the four-cornered rectangle or square that is the most common shape in any interface or texture. The GPU never draws it directly; it splits the quad along a diagonal into two triangles and draws those.

```text
A quad (quadrilateral) is two triangles:

   v0 -------- v1            v0 -------- v1
    |          |              |  \       |
    |          |      ->      |    \     |
    |          |              |      \   |
   v3 -------- v2            v3 -------- v2
                              (triangle A: v0, v1, v3)
                              (triangle B: v1, v2, v3)
```

A model is thus two lists: a list of **vertices**, each a point in space, and a list of **triangles**, each a triple of indices into the vertex list. This structure is a _triangle mesh_. To the hardware a sphere is not a sphere but a few hundred triangles arranged so that the silhouette appears curved.[^fn:4]

```text
A "sphere" is a triangle mesh; the curve is an illusion of fine subdivision:

            __--+--+--__              every face is a flat triangle,
         _-- \  |  | /  --_           but enough of them around the
        +-----+--+--+-----+           silhouette read as a smooth
        |\    |\ | /|    /|           curve. Coarse mesh: the facets
        | \   | \|/ |   / |           show. Finer mesh: the same
        +--+--+--+--+--+--+           triangles, smaller, and the
        | /   | /|\ |   \ |           outline rounds off.
        |/    |/ | \|    \|
        +-----+--+--+-----+
         --_ /  |  | \ _--
            --__+--+__--
```

The input to the pipeline is therefore fixed: a set of vertices and a set of triangles.


## The Central Problem: Space Is Three-Dimensional, the Screen Is Not {#the-central-problem-space-is-three-dimensional-the-screen-is-not}

A vertex is a triple of real numbers, for example \\((2.0,\ 1.5,\ -8.0)\\), denoting a position in some 3D coordinate system. The display is a two-dimensional array of pixels, for example \\(1920 \times 1080\\). The coordinates of the vertex do not, by themselves, name a pixel.

The mapping from one to the other depends on the observer. Moving the camera sends the same vertex to a different pixel, or off the screen entirely. The pipeline must compute, for a point defined in the world and a given camera, the pixel onto which that point projects, if any.

This computation is performed as a chain of changes of coordinate system. Each change is a linear (or, with one extension, affine) transformation, expressed as a matrix and applied to the vertex by matrix–vector multiplication. The next sections develop each link in the chain explicitly.


## Vectors, Bases, and What a Transformation Does {#vectors-bases-and-what-a-transformation-does}

A point in 3D is a column vector of its coordinates:

\\[\mathbf{p} = \begin{bmatrix} x \\\ y \\\ z \end{bmatrix}\\]

These coordinates are not absolute; they are measured against a chosen set of reference directions. Consider the numbers \\((2, 3)\\) on a sheet of graph paper: they mean "2 squares right, 3 squares up" — but only relative to a particular corner you have agreed to call the origin, and particular directions you have agreed to call right and up. Slide the origin, or turn the page, and the _same dot_ on the paper now has different numbers, even though the dot has not moved.

Those reference directions are the **basis vectors** of the coordinate system. In 3D there are three of them, written \\(\mathbf{e}\_1, \mathbf{e}\_2, \mathbf{e}\_3\\) — unit-length arrows pointing along the \\(x\\), \\(y\\), and \\(z\\) axes. To say a point has coordinates \\(\mathbf{p} = (x, y, z)\\) is shorthand for

\\[\mathbf{p} = x\\,\mathbf{e}\_1 + y\\,\mathbf{e}\_2 + z\\,\mathbf{e}\_3\\]

that is, "go \\(x\\) steps along the first axis, \\(y\\) along the second, \\(z\\) along the third." The coordinates are the recipe; the basis vectors are the units the recipe is written in. Change the basis — pick different axes, as the camera and the screen each do — and the same physical point gets a different coordinate triple.

This is the key idea behind the whole geometry stage: rendering does not so much move objects through the world as re-express the same fixed points against one set of basis vectors after another — the model's, then the world's, then the camera's — until the final basis _is_ the screen itself.

A **linear transformation** \\(T\\) is a function on vectors that respects addition and scaling:

\\[T(\mathbf{a} + \mathbf{b}) = T(\mathbf{a}) + T(\mathbf{b}), \qquad T(s\\,\mathbf{a}) = s\\,T(\mathbf{a})\\]

Any such \\(T\\) in three dimensions is completely determined by what it does to the three basis vectors. If \\(T(\mathbf{e}\_1), T(\mathbf{e}\_2), T(\mathbf{e}\_3)\\) are known, then for any vector,

\\[T(\mathbf{p}) = x\\,T(\mathbf{e}\_1) + y\\,T(\mathbf{e}\_2) + z\\,T(\mathbf{e}\_3)\\]

Stacking \\(T(\mathbf{e}\_1), T(\mathbf{e}\_2), T(\mathbf{e}\_3)\\) as the columns of a matrix \\(M\\) gives the matrix form: \\(T(\mathbf{p}) = M\mathbf{p}\\). A matrix is, concretely, a record of where the basis vectors are sent. Rotation, scaling, and shear are all linear and all expressible this way.

\\[M\mathbf{p} = \begin{bmatrix} \vert & \vert & \vert \\\ T(\mathbf{e}\_1) & T(\mathbf{e}\_2) & T(\mathbf{e}\_3) \\\ \vert & \vert & \vert \end{bmatrix} \begin{bmatrix} x \\\ y \\\ z \end{bmatrix}\\]


## Homogeneous Coordinates: Making Translation Linear {#homogeneous-coordinates-making-translation-linear}

One operation the pipeline needs is not linear: **translation**, the simple displacement \\(\mathbf{p} \mapsto \mathbf{p} + \mathbf{t}\\). It fails the test, since \\(T(\mathbf{a}+\mathbf{b})\\) would add the offset \\(\mathbf{t}\\) twice. A \\(3\times3\\) matrix cannot express it, because \\(M\mathbf{0} = \mathbf{0}\\) — a linear map fixes the origin, but translation moves it.

The standard resolution is to embed 3D points in a 4D space by appending a coordinate \\(w = 1\\):

\\[\mathbf{p} = (x, y, z) \quad\longrightarrow\quad \tilde{\mathbf{p}} = (x, y, z, 1)\\]

These are **homogeneous coordinates**. In this 4D representation, translation becomes a _linear_ map, expressible as a single \\(4\times4\\) matrix:

\\[\begin{bmatrix} x' \\\ y' \\\ z' \\\ 1 \end{bmatrix} = \begin{bmatrix} 1 & 0 & 0 & t\_x \\\ 0 & 1 & 0 & t\_y \\\ 0 & 0 & 1 & t\_z \\\ 0 & 0 & 0 & 1 \end{bmatrix} \begin{bmatrix} x \\\ y \\\ z \\\ 1 \end{bmatrix} = \begin{bmatrix} x + t\_x \\\ y + t\_y \\\ z + t\_z \\\ 1 \end{bmatrix}\\]

Multiplying out the fourth row confirms the construction: the bottom row \\((0,0,0,1)\\) preserves \\(w = 1\\), and the right column injects the translation. The general \\(4\times4\\) transform combines a \\(3\times3\\) linear block (the entries \\(r\_{ij}\\), doing rotation and scale) with a translation column \\((t\_x, t\_y, t\_z)\\):

\\[M = \begin{bmatrix} r\_{11} & r\_{12} & r\_{13} & t\_x \\\ r\_{21} & r\_{22} & r\_{23} & t\_y \\\ r\_{31} & r\_{32} & r\_{33} & t\_z \\\ 0 & 0 & 0 & 1 \end{bmatrix}\\]

This unification has a direct consequence for the hardware. Every transform in the pipeline — placing a model, positioning the camera, applying perspective — is now a single \\(4\times4\\) matrix. A chain of transforms is the product of their matrices, computed once, and then applied to every vertex as one matrix–vector multiply. The basic arithmetic the geometry stage demands is therefore the $4&times;4$-by-4 multiply, and this is exactly the operation the GPU's vertex hardware is built to perform at high throughput.


## The Coordinate Chain {#the-coordinate-chain}

A vertex passes through five coordinate systems on the way to the screen. Each transition is one matrix multiply; the final two steps add a division and a rescaling.

```text
Local (model) space    coordinates relative to the model's own origin
    |  x Model matrix M        place the model into the world
    v
World space            coordinates in the shared scene
    |  x View matrix V         re-express relative to the camera
    v
View (camera) space    coordinates relative to the camera at the origin
    |  x Projection matrix P   apply perspective
    v
Clip space             4D homogeneous coordinates, pre-division
    |  / w   (perspective divide)
    v
NDC  [-1, 1]^3         normalized device coordinates
    |  x Viewport transform
    v
Screen space (pixels)  final (x, y) on the display
```

The composite \\(P \cdot V \cdot M\\) is precomputed once per object, so that each of its vertices is transformed by a single matrix.[^fn:5] We now examine the three matrices in turn.


### The Model Matrix: Placing an Object in the World {#the-model-matrix-placing-an-object-in-the-world}

A mesh is authored in its own _local_ coordinate system, with its origin at some natural center. The model matrix \\(M\\) maps local coordinates to _world_ coordinates — the single shared system in which all objects coexist. It is an ordinary \\(4\times4\\) transform: it rotates the model to its orientation, scales it to its size, and translates it to its location. A scene with a hundred objects has a hundred model matrices, one per object, each placing its mesh into the common world.


### The View Matrix: Changing the Origin to the Camera {#the-view-matrix-changing-the-origin-to-the-camera}

The camera occupies some position \\(\mathbf{c}\\) in world space and looks in some direction. We want each vertex expressed not in world coordinates but in coordinates _relative to the camera_: how far in front of the camera, how far to its right, how far above it. In that system the camera sits at the origin and looks down a fixed axis (by convention, the \\(-z\\) axis).

```text
               +y (up)
                |
                |        near        object
                |      (screen)        [#]
      camera    |         |             |
        O-------+---------+-------------+---------->  -z (forward)
      (origin)  |         |             |
                |                     farther
                |                     from camera
               -y

Looking down the -z axis: everything visible has a negative z, and
the more negative the z, the farther away. The screen is a plane a
short distance in front of the camera.
```

The essential observation is that there is no "camera object" in the hardware. Rendering relative to a camera is achieved by moving the _entire world_ so that the camera lands at the origin, oriented along the fixed axis. If the camera were translated by \\(\mathbf{c}\\) to reach its position, then expressing the world relative to it requires translating everything by \\(-\mathbf{c}\\); if the camera were rotated by \\(R\\) to face its direction, the world must be rotated by \\(R^{-1}\\). The view matrix is precisely this inverse of the camera's placement:

\\[V = (\text{camera placement})^{-1}\\]

"Changing the origin" therefore means: subtract the camera's position from every point so that the camera's location becomes \\((0,0,0)\\), and rotate so that its viewing direction becomes the reference axis. After applying \\(V\\), a vertex's coordinates state its position as the camera sees it. A point with a large negative \\(z\\) in view space is far in front of the camera; a point with positive \\(z\\) is behind it and will not be drawn.

Concretely, for a camera at position \\(\mathbf{c}\\) with orthonormal axes — right \\(\mathbf{r}\\), up \\(\mathbf{u}\\), and forward \\(\mathbf{f}\\) (the direction the camera looks along) — the view matrix is

\\[V = \begin{bmatrix} r\_x & r\_y & r\_z & -\mathbf{r}\cdot\mathbf{c} \\\ u\_x & u\_y & u\_z & -\mathbf{u}\cdot\mathbf{c} \\\ -f\_x & -f\_y & -f\_z & \mathbf{f}\cdot\mathbf{c} \\\ 0 & 0 & 0 & 1 \end{bmatrix}\\]

The upper \\(3\times3\\) block rotates world axes onto the camera's axes; the right column translates by the camera's position projected onto those axes. Reading the top row, the new $x$-coordinate of a point is its displacement from the camera measured along the camera's right vector — exactly "how far to the right of the camera is this point." The third row carries \\(-\mathbf{f}\\) rather than \\(\mathbf{f}\\): because the camera looks down \\(-z\\) by convention, a point in front of the camera (along \\(+\mathbf{f}\\)) must receive a negative view-space \\(z\\), which the negation provides. The view transform is, in total, a change of basis from the world's basis vectors to the camera's.


### The Projection Matrix: Producing Perspective {#the-projection-matrix-producing-perspective}

In view space the camera is at the origin looking down \\(-z\\). The remaining task is perspective: distant objects must appear smaller, and lines receding from the viewer must converge.

The region the camera can see is a **view frustum** — a rectangular pyramid with its apex at the camera, truncated by a near plane and a far plane. Geometry inside the frustum is potentially visible; geometry outside is removed.

```text
         far plane
       +---------------+
       |               |       The projection matrix maps this
       |   +-------+   |       truncated pyramid onto a cube. Because
       |   | near  |   |       the wide far plane is compressed to the
eye .......| plane |   |       same cube width as the narrow near
       |   +-------+   |       plane, objects at the far plane are
       |               |       scaled down -- this is perspective.
       +---------------+
```

Perspective comes down to a single operation: **divide the screen position by the distance from the camera.**[^fn:6] A point at view-space position \\((x, y, z)\\) projects to a screen position of roughly

\\[\left(\frac{x}{-z},\ \frac{y}{-z}\right)\\]

(the camera looks down \\(-z\\), so \\(-z\\) is the positive distance in front of it). Dividing by that distance is the whole of perspective. To see why, take two pillars of equal height \\(y = 2\\):

```text
near pillar at z = -2  ->  screen height = 2 / 2  = 1.0
far  pillar at z = -10 ->  screen height = 2 / 10 = 0.2
```

The pillars are the same size in the world, but the far one occupies one-fifth the height on screen, purely because it was divided by a larger distance. This is exactly what the eye and a camera lens do, and it is the entire content of perspective: closer means divided by less, so it appears bigger.

The difficulty is mechanical. Division is not a linear operation, so it cannot be written as a matrix entry — yet every other stage of the pipeline is a matrix multiply, and we would like this one to fit the same machinery. Homogeneous coordinates resolve it. The projection matrix is constructed so that, rather than leaving \\(w = 1\\), it writes the distance \\(-z\\) into the \\(w\\) component. The division by \\(w\\) is then performed as one separate step afterward, applied uniformly to every vertex. For a frustum with near distance \\(n\\), far distance \\(f\\), and a vertical field of view encoded in a focal term, a representative projection matrix is

\\[P = \begin{bmatrix} \frac{1}{a \cdot \tan(\theta/2)} & 0 & 0 & 0 \\\ 0 & \frac{1}{\tan(\theta/2)} & 0 & 0 \\\ 0 & 0 & \frac{-(f+n)}{f-n} & \frac{-2fn}{f-n} \\\ 0 & 0 & -1 & 0 \end{bmatrix}\\]

where \\(\theta\\) is the field of view and \\(a\\) the aspect ratio. The detail that matters is the bottom row, \\((0, 0, -1, 0)\\). Multiplying it against a view-space point \\((x, y, z, 1)\\) produces \\(w' = -z\\) — the new \\(w\\) holds exactly the distance we want to divide by. After the matrix multiply the vertex is in **clip space**, a 4D coordinate whose \\(w\\) now carries that distance.

The division is then performed as a separate step, the **perspective divide**:

\\[(x\_{\text{ndc}},\ y\_{\text{ndc}},\ z\_{\text{ndc}}) = \left(\frac{x\_{\text{clip}}}{w},\ \frac{y\_{\text{clip}}}{w},\ \frac{z\_{\text{clip}}}{w}\right)\\]

Because \\(w = -z\\), this is the same \\(x/(-z)\\) and \\(y/(-z)\\) from the pillar example — the matrix did not perform the perspective division, it merely arranged for the right number to be sitting in \\(w\\) so the division can be done in one uniform step. Distant geometry, divided by a larger \\(w\\), shrinks by exactly the factor perspective requires. The result lies in **normalized device coordinates** (NDC), the cube \\([-1,1]^3\\), in which \\(x\\) and \\(y\\) are screen position and \\(z\\) is normalized depth.


### Clipping and the Viewport Transform {#clipping-and-the-viewport-transform}

Two mechanical steps complete the geometry stage. **Clipping** discards triangles wholly outside the cube and cuts those that cross its boundary, introducing new vertices along the cut so that the rasterizer never receives geometry extending past the framebuffer. The **viewport transform** then maps the \\([-1,1]\\) square in \\(x\\) and \\(y\\) onto actual pixel ranges, \\([0, 1919]\\) and \\([0, 1079]\\), by a scale and an offset. After it, every surviving vertex has integer-addressable screen coordinates and a depth value. The geometry stage has answered, for all three corners of every triangle, which pixel the corner projects onto.


## Rasterization: From Triangles to Fragments {#rasterization-from-triangles-to-fragments}

The input to this stage is a set of triangles with screen-space corners. Rasterization determines which pixels each triangle covers. It is the three-dimensional successor to the 2D scanline fill of Part 1, extended with attribute interpolation and depth.

For each triangle the rasterizer examines the pixels within its bounding rectangle and tests whether each pixel center lies inside the triangle. The test uses three **edge functions**. For a directed edge from vertex \\(\mathbf{a}\\) to vertex \\(\mathbf{b}\\), the function

\\[E(\mathbf{p}) = (\mathbf{b} - \mathbf{a}) \times (\mathbf{p} - \mathbf{a})\\]

is the $z$-component of a cross product; its sign indicates which side of the edge \\(\mathbf{p}\\) lies on. A pixel is inside the triangle when all three edge functions share the same sign.[^fn:3] Three multiply–subtract evaluations and three sign tests decide coverage, with no branching — again a consequence of the convexity guaranteed in the first section.

A covered pixel does not yet have a color. The rasterizer emits a **fragment**: a candidate pixel carrying the data required to finish it — screen position, an interpolated depth, and interpolated attributes (color, texture coordinates, surface normal) derived from the triangle's three vertices.


### Barycentric Interpolation {#barycentric-interpolation}

Each vertex carries attributes; a fragment lies in the interior. Its attribute values are a weighted average of the three vertices' values, with weights given by **barycentric coordinates** \\((\lambda\_0, \lambda\_1, \lambda\_2)\\). These are the relative areas of the three sub-triangles formed by the fragment and the edges, normalized so that

\\[\lambda\_0 + \lambda\_1 + \lambda\_2 = 1, \qquad \lambda\_i \geq 0 \text{ inside the triangle}\\]

The same edge functions evaluated during the coverage test yield these areas directly, so the weights are a byproduct of work already done. Any attribute \\(A\\) is then interpolated as

\\[A(\mathbf{p}) = \lambda\_0 A\_0 + \lambda\_1 A\_1 + \lambda\_2 A\_2\\]

This one mechanism produces a smooth color gradient across a flat triangle, and it is how a texture image is mapped onto geometry: each vertex carries a texture coordinate, the coordinate is interpolated per fragment, and the interpolated value indexes into the texture.

One correction is required in practice. Interpolating attributes linearly in _screen_ space is wrong once perspective is involved, because the perspective divide is non-linear: equal steps across the screen do not correspond to equal steps across the surface in space. The hardware therefore performs _perspective-correct_ interpolation — it interpolates \\(A/w\\) and \\(1/w\\) linearly in screen space, then divides the two at each fragment to recover \\(A\\). The barycentric weights are the same; the quantities they are applied to are divided by \\(w\\) first.


### The Depth Buffer {#the-depth-buffer}

Triangles are submitted in arbitrary order. A distant wall may be drawn after the near figure standing in front of it; drawn naively, the wall would overwrite the figure. The NES avoided this by assigning fixed layers. A general 3D scene has no fixed layering and must resolve visibility per pixel.

The mechanism is a second buffer, the **depth buffer**, holding for each pixel the depth of the nearest surface drawn there so far.[^fn:7] When a fragment arrives, its interpolated depth is compared against the stored value:

```text
for each fragment at (x, y) with depth z:
    if z < depth[x][y]:          # nearer than the current occupant
        color[x][y] = fragment.color
        depth[x][y] = z
    else:                        # something nearer is already present
        discard the fragment
```

Visibility is resolved with one comparison per fragment, requiring no sorting and no knowledge of any other triangle. The comparison for a fragment at \\((x, y)\\) reads and writes only that pixel's slot, so it shares no state with the comparison at any other pixel. The fragments are mutually independent, in the precise sense that the result at one pixel is a function of that pixel's slot alone. This is the same independence identified in Part 1, now extended to carry a depth value; it is the property that allows the depth test, and the fragment work generally, to be performed across many pixels simultaneously.


## The Assembled Pipeline {#the-assembled-pipeline}

Composing the stages yields the standard graphics pipeline, the form fixed in hardware before any stage was programmable.[^fn:8]

```text
Vertices + triangles (the mesh)
     |
     v
Vertex processing      apply M, V, P -> vertices in clip space
     |
     v
Clip + divide + viewport   cull and clip, perspective divide,
     |                     map to screen-space triangles
     v
Rasterization          edge test -> covered pixels;
     |                 emit fragments with interpolated attributes
     v
Fragment processing    texture lookup, lighting -> fragment color
     |
     v
Depth test + blend     z-buffer comparison, alpha blend
     |
     v
Framebuffer -> display
```

The pipeline has a characteristic shape. The top operates per vertex, on the order of thousands of elements; the bottom operates per fragment, on the order of millions. At both levels the elements are independent: no vertex's transform reads another vertex, and no fragment's color reads another fragment. The arithmetic is uniform — the same matrix multiply for every vertex, the same shading computation for every fragment. Hardware suited to this workload need not be sophisticated in control flow; it must apply one short program to a large number of independent elements at once. The structure of the pipeline is, in this sense, the specification of the machine that runs it.

```text
The hardware mirrors the workload: a grid of small, identical cores, each
running the same short program on a different element.

   GPU
   +-----------------------------------------------+
   |  +-------+  +-------+  +-------+  +-------+   |
   |  | core  |  | core  |  | core  |  | core  |   |   one shader
   |  +-------+  +-------+  +-------+  +-------+   |   program, run
   |  +-------+  +-------+  +-------+  +-------+   |   over thousands
   |  | core  |  | core  |  | core  |  | core  |   |   of vertices /
   |  +-------+  +-------+  +-------+  +-------+   |   millions of
   |  +-------+  +-------+  +-------+  +-------+   |   fragments, all
   |  | core  |  | core  |  | core  |  | core  |   |   independent
   |  +-------+  +-------+  +-------+  +-------+   |
   |  ( ... hundreds to thousands of cores ... )   |
   +-----------------------------------------------+

   Wide, not clever: simple control flow, many lanes, one program.
```


## Programmable Stages: Shaders {#programmable-stages-shaders}

The early pipeline was **fixed-function**: lighting, texturing, and blending were hardwired, configurable only from a fixed menu. Fog could be enabled but not redefined. Two stages were later replaced by small programs, supplied by the application and executed by the hardware once per element.

A **vertex shader** runs once per vertex. Its required output is the clip-space position, the product \\(P V M \mathbf{p}\\). Being a program, it can additionally perform per-vertex computation such as skeletal animation or procedural displacement.

A **fragment shader** runs once per fragment and outputs its color. Lighting models, texture combination, and surface effects are computed here.

The execution model is fixed by the hardware: a shader is one program run over a large batch of independent elements concurrently. A fragment shader has no access to the results of other fragments, because the hardware executes them in parallel with no defined ordering or communication between them. The independence observed earlier is therefore not merely a property of the data but a constraint enforced by the execution model — a fragment shader is _forbidden_ from depending on its neighbors, and this restriction is what permits the parallel execution in the first place. The same constraint reappears in later parts, where the elements are not fragments but tensor components.


## The API Layer: OpenGL and Vulkan {#the-api-layer-opengl-and-vulkan}

The pipeline described above is what the hardware performs, but a program running on the CPU cannot poke the GPU directly: the mesh, the matrices, and the shaders all live in the application's memory, and something must hand them to the hardware, allocate GPU memory, bind the shaders, and launch the draw. That intermediary is an **application programming interface** (API) — the layer through which a program drives the hardware.

The open question an API must answer is **who does the hard part.** Driving the GPU involves real work — tracking state, validating it, allocating and synchronizing memory, scheduling the draws — and that work can live either inside the driver or inside the application. OpenGL and Vulkan target the same silicon and produce the same pixels; they are two opposite answers to this one question, distinguished by how much of the machine they expose and how much they manage on the program's behalf.


### OpenGL: The Pipeline as a State Machine {#opengl-the-pipeline-as-a-state-machine}

OpenGL (1992) models the hardware as a **state machine** configured incrementally. The program issues calls that set state — bind a texture, select a blend mode, choose a shader — and then a draw call renders using whatever state is currently bound. The driver records the state, validates it, manages memory, and schedules the work.

```text
glUseProgram(shader);                  // set current shader
glBindTexture(GL_TEXTURE_2D, tex);     // set current texture
glBindBuffer(GL_ARRAY_BUFFER, vbo);    // set current vertex data
glDrawArrays(GL_TRIANGLES, 0, n);      // draw with the bound state
```

The interface is compact, and the driver performs the difficult tasks of allocation and scheduling. The cost is that substantial work occurs inside the driver on each call — state tracking, validation, inference of intent — and this work is difficult to distribute across CPU threads. As scenes grew to tens of thousands of draw calls per frame, the driver became the limiting factor.


### Vulkan: Explicit Control {#vulkan-explicit-control}

Vulkan (2016) inverts the division of responsibility. Rather than a state machine that conceals the hardware, it exposes the hardware closely and assigns to the application the work the OpenGL driver had performed: allocating GPU memory, compiling pipeline configuration into immutable objects ahead of time, recording commands into **command buffers**, and submitting those buffers explicitly to hardware queues.

```text
OpenGL:  application -> [ thick driver: allocation, state, scheduling ] -> GPU
Vulkan:  application -> [ thin driver ] -> GPU
         the application allocates memory, manages synchronization,
         records command buffers, and submits them to queues
```

This buys control at the cost of verbosity. Drawing one triangle takes a few calls in OpenGL but on the order of a thousand lines of setup in Vulkan. What the application gets back for that effort is direct control over memory and scheduling, performance that no longer depends on a driver guessing its intent, and — the change that actually mattered — the ability to record command buffers on several CPU threads at once, because there is no hidden global driver state left to serialize them.[^fn:9] The shift makes sense once you notice that the GPU is a parallel machine fed by a parallel CPU; OpenGL had been handing that hardware a single-threaded, sequential contract, and Vulkan simply stops doing so.


## Conclusion {#conclusion}

The 3D pipeline answers one question — which pixel does a triangle in space project onto, and what is its color — by composing a sequence of coordinate transformations with a fill. The geometry stage is linear algebra: points are re-expressed from one basis to the next by matrix multiplication, translation is linearized by a fourth coordinate, the camera is realized by moving the world so the camera lies at the origin, and perspective is produced by a single division by that fourth coordinate. Rasterization tests coverage with edge functions, interpolates attributes by barycentric weights, and resolves visibility with a per-pixel depth comparison.

Across every stage that processes many elements, the elements are independent: each vertex is transformed in isolation, each fragment is shaded and depth-tested in isolation. This is the same property established for 2D rendering in Part 1, now extended through three dimensions and carrying depth and texture. It determines the shape of the hardware — wide rather than clever — and it is enforced as a rule on the programmable stages. Part 3 takes this hardware, a machine that applies one program to many independent elements, and applies it to computations that have nothing to do with triangles.

---

From Pixels to Tensors Series:

-   Part 1: [2D Rendering Baselines](@/technical/pixels-to-tensors/part-1-2d-rendering.md)
-   Part 2: The 3D Graphics Pipeline

---

<br>

**Footnotes**

[^fn:1]: [Branch Education — How do Graphics Cards Work?](https://www.youtube.com/watch?v=h9Z4oGN89MU)
[^fn:2]: Scratchapixel, [Why Are Triangles Useful in Computer Graphics?](https://www.scratchapixel.com/lessons/3d-basic-rendering/ray-tracing-rendering-a-triangle/why-are-triangles-useful.html). States the case directly: a triangle is coplanar by construction (its three vertices always delineate one plane, unlike quads and higher polygons), is the simplest polygon to test and rasterize, and any other geometry can be triangulated into coplanar triangles — so a renderer needs only one optimized routine. The convexity and edge-test argument is made precise in Pineda&nbsp;[^fn:3].
[^fn:3]: Juan Pineda, ["A Parallel Algorithm for Polygon Rasterization"](https://dl.acm.org/doi/10.1145/54852.378457), SIGGRAPH 1988 (Computer Graphics, vol. 22, no. 4). Introduces the linear edge function whose sign determines which side of an edge a point lies on.
[^fn:4]: [Approximating Spheres with Triangles](https://eugene-eeo.github.io/blog/sphere-triangles.html). Works through recursive subdivision schemes (edge, midpoint, and centroid) that start from an octahedron and repeatedly lift new points onto the sphere — a concrete look at how a curved surface is built from a fine triangle mesh.
[^fn:5]: [LearnOpenGL — Coordinate Systems](https://learnopengl.com/Getting-started/Coordinate-Systems). Defines the five spaces (local, world, view, clip, screen), the multiplication order \\(V\_{clip} = M\_{proj} \cdot M\_{view} \cdot M\_{model} \cdot V\_{local}\\), and the perspective divide by \\(w = -z\\).
[^fn:6]: [Tsoding - One Formula That Demystifies 3D Graphics](https://www.youtube.com/watch?v=qjWkNZ0SXfo)
[^fn:7]: Edwin Catmull, ["A Subdivision Algorithm for Computer Display of Curved Surfaces"](https://archive.org/details/DTIC_ADA004968), Ph.D. dissertation, University of Utah, 1974. Source of the z-buffer / depth-buffer method for hidden-surface removal.
[^fn:8]: [A Trip through the Graphics Pipeline](https://alaingalvan.gitbook.io/a-trip-through-the-graphics-pipeline)
[^fn:9]: [Khronos — Vulkan API announcement](https://www.khronos.org/news/press/khronos-reveals-vulkan-api-for-high-efficiency-graphics-and-compute-on-gpus). States the explicit-control design: Vulkan gives "lower-level and more explicit access" by moving validation, resource tracking, and state management out of the driver and into the application, enabling multithreaded command preparation.
