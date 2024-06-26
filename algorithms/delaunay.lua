package.path = package.path .. ";../matplotlua/?.lua"
package.path = package.path .. ";./?.lua"

local Plot = require("matplotlua")
local Utils = require("utils")

local Delaunay = {}


-------- DEFAULT SCRIPT SETUP --------

DEBUG = DEBUG or false                   -- print debug messages
PLOT = PLOT or false                     -- plot each step, useful for debugging
OUT_DIR = OUT_DIR or "../figures/"       -- output directory for plots


-------- DEBUG AND PLOT --------

local function _dprint(...)
  if DEBUG then print(...) end
end

local function _plotbase(points, p, triangles)
  Plot.addPointList(points, "blue")
  for _,t in ipairs(triangles) do
    Plot.addPolygon(t.vertices, nil, "blue")
  end
  Plot.addPoint(p.x, p.y, "red")
end

local function _plotcircles(points, i, p, triangles, bad_triangles)
  if not PLOT then return end
  Plot.init{title = "Delaunay Triangulation (point " .. i .. ", circumcircles)"}
  _plotbase(points, p, triangles)
  for _,t in ipairs(bad_triangles) do
    Plot.addPolygon(t.triangle.vertices, nil, "red")
    Plot.addCircle(t.triangle.circumcircle, nil, "green")
  end
  Plot.saveFrame()
end

local function _plotstep1(points, i, p, triangles)
  if not PLOT then return end
  Plot.init{title = "Delaunay Triangulation (point " .. i .. ", step 1)"}
  _plotbase(points, p, triangles)
  Plot.saveFrame()
end

local function _plotstep2(points, i, p, triangles, bad_triangles)
  if not PLOT then return end
  Plot.init{title = "Delaunay Triangulation (point " .. i .. ", step 2)"}
  _plotbase(points, p, triangles)
  for _,t in ipairs(bad_triangles) do
    Plot.addPolygon(t.triangle.vertices, nil, "red")
  end
  Plot.saveFrame()
end

local function _plotstep3(points, i, p, triangles, polygon)
  if not PLOT then return end
  Plot.init{title = "Delaunay Triangulation (point " .. i .. ", step 3)"}
  _plotbase(points, p, triangles)
  for _,e in ipairs(polygon) do
    Plot.addLine(e[1], e[2], nil, "red")
  end
  Plot.saveFrame()
end

local function _plotstep4(points, i, p, triangles, new_triangles)
  if not PLOT then return end
  Plot.init{title = "Delaunay Triangulation (point " .. i .. ", step 4)"}
  _plotbase(points, p, triangles)
  for _,t in ipairs(new_triangles) do
    Plot.addPolygon(t.vertices, nil, "red")
  end
  Plot.saveFrame()
end

local function _plotstep5(points, triangles, removed_triangles)
  if not PLOT then return end
  Plot.init{title = "Delaunay Triangulation Final Step"}
  Plot.addPointList(points, "blue")
  for _,t in ipairs(triangles) do
    Plot.addPolygon(t.vertices, nil, "blue")
  end
  for _,t in ipairs(removed_triangles) do
    Plot.addPolygon(t.vertices, nil, "red")
  end
  Plot.saveFrame()
end

local function _plotresults(points, triangles)
  if not PLOT then return end
  Plot.init{title = "Delaunay Triangulation Final Results"}
  Plot.addPointList(points, "blue")
  for _,t in ipairs(triangles) do
    Plot.addPolygon(t.vertices, nil, "blue")
  end
  Plot.saveFrame()
end


-------- AUXILIAR --------

-- given 3 points, return the circumcircle of the triangle they form
-- solve the system of equations described at https://en.wikipedia.org/wiki/Circumcircle
local function _circumcircle(p1, p2, p3)
  local A = p2.x - p1.x
  local B = p2.y - p1.y
  local C = p3.x - p1.x
  local D = p3.y - p1.y
  local E = A * (p1.x + p2.x) + B * (p1.y + p2.y)
  local F = C * (p1.x + p3.x) + D * (p1.y + p3.y)
  local G = 2 * (A * (p3.y - p2.y) - B * (p3.x - p2.x))

  local x, y
  if math.abs(G) < 0.000001 then
    -- points are co-linear
    x = ((p1.x + p3.x) - (p1.x + p2.x)) / 2
    y = ((p1.y + p3.y) - (p1.y + p2.y)) / 2
  else
    x = (D * E - B * F) / G
    y = (A * F - C * E) / G
  end

  return {x = x, y = y, r = math.sqrt((p1.x - x)^2 + (p1.y - y)^2)}
end

-- given a point and a triangle, checks if the point is inside the circumcircle of the triangle
local function _incircle(p, t)
  return ((p.x - t.circumcircle.x)^2 + (p.y - t.circumcircle.y)^2) <= t.circumcircle.r^2
end

-- given a list of points, returns a supertriangle that contains all points
local function _supra_triangle(points)
  local xmin, ymin, xmax, ymax = math.huge, math.huge, -math.huge, -math.huge
  for _, p in ipairs(points) do
    xmin, ymin = math.min(xmin, p.x), math.min(ymin, p.y)
    xmax, ymax = math.max(xmax, p.x), math.max(ymax, p.y)
  end

  -- center
  local cx = (xmin + xmax) / 2
  local cy = (ymin + ymax) / 2

  -- M is the maximum distance from center to a corner
  local M = (xmax-xmin > ymax-ymin) and xmax-cx or ymax-cy

  return Delaunay.Triangle(
    {x = cx,     y = cy+3*M}, -- top
    {x = cx-3*M, y = cy-3*M}, -- left    
    {x = cx+3*M, y = cy}      -- right
  )
end

-- check if two edges are the same, regardless of the order of the vertices
local function _edge_equal(e1, e2)
  return (e1[1] == e2[1] and e1[2] == e2[2]) or (e1[1] == e2[2] and e1[2] == e2[1])
end

-- check if an edge of a triangle is shared by any other triangle
-- skip_index is the index of the original triangle (to avoid checking itself)
local function _bad_edge(e, bad_triangles, skip_index)
  for _, t in ipairs(bad_triangles) do
    if t.index ~= skip_index and Utils.listIsSubset(t.triangle.vertices, e) then
      return true
    end
  end
  return false
end



-------- DATA STRUCTURES --------

function Delaunay.Triangle(p1, p2, p3)
  return {
    vertices = {p1, p2, p3},
    circumcircle = _circumcircle(p1, p2, p3),
    edges = {
      {p1, p2},
      {p2, p3},
      {p3, p1},
    },
  }
end



------ ALGORITHMS ------

-- Bowyer-Watson algorithm
function Delaunay.incremental(points)
  local supra = _supra_triangle(points)
  local triangles = {supra}

  for pi,p in ipairs(points) do
    -- step 1: add a new point to the triangulation
    _dprint("-------------------------- " .. pi .. " --------------------------")
    _plotstep1(points, pi, p, triangles)


    -- step 2: find triangles that are no longer valid due to the insertion and remove them from the mesh
    local bad_triangles = {}
    for ti, t in ipairs(triangles) do
      if _incircle(p, t) then
        table.insert(bad_triangles, {index = ti, triangle = t})
      end
    end
    _dprint("#bad_triangles = "..#bad_triangles)
    for i=#bad_triangles,1,-1 do
      table.remove(triangles, bad_triangles[i].index)
      _dprint("removed triangle, #triangles = "..#triangles)
    end
    _plotstep2(points, pi, p, triangles, bad_triangles)
    -- _plotcircles(points, pi, p, triangles, bad_triangles)


    -- step 3: find the polygonal hole left by the bad triangles
    local polygon = {} -- list of edges
    for _, bad_t in ipairs(bad_triangles) do
      for _, e in ipairs(bad_t.triangle.edges) do
        if not _bad_edge(e, bad_triangles, bad_t.index) then
          table.insert(polygon, e)
        end
      end
    end
    _dprint("#polygon = "..#polygon)
    _plotstep3(points, pi, p, triangles, polygon)


    -- step 4: re-triangulate the polygonal hole
    local new_triangles = {}
    for _, e in ipairs(polygon) do
      local t = Delaunay.Triangle(p, e[1], e[2])
      table.insert(new_triangles, t)
      table.insert(triangles, t)
    end
    _dprint("#new_triangles = "..#new_triangles)
    _dprint("#triangles = "..#triangles)
    _plotstep4(points, pi, p, triangles, new_triangles)
  end

  -- final step: remove all triangles that contain a vertex of the supra-triangle
  local removed_triangles = {}
  for i=#triangles,1,-1 do
    for _, v in ipairs(supra.vertices) do
      if Utils.listContains(triangles[i].vertices, v) then
        table.insert(removed_triangles, table.remove(triangles, i))
        break
      end
    end
  end
  _plotstep5(points, triangles, removed_triangles)
  _plotresults(points, triangles)
  return triangles
end




return Delaunay
