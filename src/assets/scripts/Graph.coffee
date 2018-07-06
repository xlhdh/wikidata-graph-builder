itemLabel = (el) -> el.itemLabel?.value ||
                    el.item.value.match("^http://www\.wikidata\.org/entity/(.+)$")?[1] ||
                    el.item.value

prepareData = (data) ->
  hasSize = "size" in data.head.vars

  bindings = data.results.bindings
  minSize = Infinity
  maxSize = 0

  nodes = {}
  if hasSize
    for el in bindings
      continue if nodes[el.item.value]
      size = parseInt el.size.value
      minSize = size if size < minSize
      maxSize = size if size > maxSize

      nodes[el.item.value] =
        name: itemLabel el
        url: el.item.value
        hasLink: !!el.linkTo
        size: size
  else
    for el in bindings
      nodes[el.item.value] =
        name: itemLabel el
        url: el.item.value
        hasLink: !!el.linkTo

  links = (source: nodes[el.item.value], target: nodes[el.linkTo.value] for el in bindings when nodes[el.linkTo?.value])

  {hasSize, nodes, links, minSize, maxSize}

insertData = (graph, data, activeItem, mode, sizeLogScale) ->
  graph.selectAll("*").remove()
  d3.selectAll("#graph-tooltip").remove()

  return if not data or not data.head

  {hasSize, nodes, links, minSize, maxSize} = prepareData data

  if hasSize
    useLogScale = sizeLogScale
    scaleRange = [3, 20]
    if useLogScale
      radscaler = d3.scale.log().clamp(true).domain([Math.max(1e-12, minSize), Math.max(1e-12, maxSize)]).range(scaleRange)
    else
      radscaler = d3.scale.linear().domain([minSize, maxSize]).range(scaleRange)

    for nodeid, node of nodes
      node.radius = radscaler node.size


  svg = graph.append('svg')
  svg.attr("xmlns", "http://www.w3.org/2000/svg")
  svg.attr("xlink", "http://www.w3.org/1999/xlink")
  tooltip = d3.select("body").append("div")
  tooltip.attr("class", "tooltip")
  tooltip.style("opacity", 0)

  transform = (d) -> "translate(#{d.x},#{d.y})"

  tick = ->
    if hasSize
      length = ({x, y}) -> Math.sqrt(x*x + y*y)
      sum = ({x:x1, y:y1}, {x:x2, y:y2}) -> x: x1+x2, y: y1+y2
      diff = ({x:x1, y:y1}, {x:x2, y:y2}) -> x: x1-x2, y: y1-y2
      prod = ({x, y}, scalar) -> x: x*scalar, y: y*scalar
      div = ({x, y}, scalar) -> x: x/scalar, y: y/scalar
      scale = (vector, scalar) -> prod vector, scalar / length vector

      line
      .each (d) ->
        {source, target} = d
        if source.x is target.x and source.y is target.y
          d.sp = source
          d.tp  = target
          return
        dvec = diff target, source
        d.sp = sum source, scale dvec, source.radius
        d.tp  = diff target, scale dvec, target.radius

        return
      line.attr('x1', ({sp}) -> source.x)
      line.attr('y1', ({sp}) -> source.y)
      line.attr('x2', ({sp}) -> target.x)
      line.attr('y2', ({sp}) -> target.y)
    else
      line.attr('x1', ({source}) -> source.x)
      line.attr('y1', ({source}) -> source.y)
      line.attr('x2', ({target}) -> target.x)
      line.attr('y2', ({target}) -> target.y)

    circle.attr('transform', transform)
    text.attr('transform', transform)
    return

  zoomed = ->
    container.attr('transform', d3.event.transform)
    return

  zoom = d3.zoom().on('zoom', zoomed)

  linkDistance = 30
  charge = -200

  simulation = d3.forceSimulation(d3.values nodes)
    .force("charge", d3.forceManyBody().strength(charge))
    .force('link', d3.forceLink().links(links))
    .force("CollideForce", d3.forceCollide()) 
  simulation.on("tick",tick)

  dragstarted = (d) ->
    if not d3.event.active
      simulation.alphaTarget(0.3).restart()
    d.fx = d.x
    d.fy = d.y
  dragged = (d) ->
    d.fx = d3.event.x
    d.fy = d3.event.y
  dragended = (d) ->
    if not d3.event.active
      simulation.alphaTarget(0)
    d.fx = null
    d.fy = null

  svg.attr("pointer-events", "all")
  svg.selectAll('*').remove()

  arrowOffset = if hasSize then 0 else 6

  marker = svg.append('defs')
    .selectAll('marker')
    .data(['direction'])
    .enter()
    .append('marker')
  marker.attr("id", ((d) -> d) )
  marker.attr("viewBox", "0 -5 10 10" )
  marker.attr("refX", 10 + arrowOffset - 1)
  marker.attr("markerWidth", 6 )
  marker.attr("markerHeight", 6 )
  marker.attr("orient", 'auto')
  path = marker.append('path')
  path.attr('d', 'M0,-5L10,0L0,5')

  svg_group = svg.append("g").attr("transform", "translate(0,0)").call(zoom)

  drag_rect = svg_group.append("rect")
            .style("fill", "none")

  container = svg_group.append("g")

  line = container
    .append('g')
    .selectAll('line')
    .data(links)
    .enter()
    .append('line')
  line.attr('marker-end', 'url(#direction)')

  radius = if hasSize then ((d) -> d.radius) else 6

  circle = container
    .append('g')
    .selectAll('circle')
    .data(simulation.nodes())
    .enter()
    .append('circle')
  circle.attr('r', radius)

  if hasSize
    tooltipFn = (d) -> "#{d.name}<br/>Size: #{d.size}"
  else
    tooltipFn = (d) -> d.name

  if hasSize
    circle
    .on "mouseover", (d) ->
      tooltip.transition().duration(100).style("opacity", .9)
      tooltip.html(tooltipFn d)
      .style("left", (d3.event.pageX + 5) + "px")
      .style("top", (d3.event.pageY + 5) + "px")
    .on "mouseout", (d) ->
      tooltip.transition().duration(200).style("opacity", 0)


  if mode is 'undirected'
    circle.classed('linked', (o) -> o.hasLink)

  circle.classed('active', (o) -> o.url.endsWith(activeItem))
  circle.call(d3.drag()
          .on("start", dragstarted)
          .on("drag", dragged)
          .on("end", dragended))

  text = container.append('g')
    .selectAll('text')
    .data(simulation.nodes())
    .enter()
    .append('text')
    .text((d) -> d.name)
    .on('click', (o) -> window.open o.url; return)
  text.attr('x', 8)
  text.attr('y', '.31em')

  width = height = 0

  resize = ->
    sidenavWidth = 300
    width = window.innerWidth - sidenavWidth
    height = window.innerHeight
    svg.attr('width', width)
    svg.attr('height', height)
    drag_rect.attr('width', width)
    drag_rect.attr('height', height)
    simulation.force("center", d3.forceCenter(width / 2, height / 2))
    return

  resize()
  d3.select(window).on 'resize', resize
  return

app = angular.module('Graph', [])

app.directive 'graph', ->
  restrict: 'E'
  replace: no
  scope:
    graphData: '='
    activeItem: '='
    mode: '='
    sizeLogScale: '='

  link: (scope, element, attrs) ->
    scope.$watch 'graphData', (newValue, oldValue) ->
      graph = d3.select(element[0])
      insertData(graph, scope.graphData, scope.activeItem, scope.mode, scope.sizeLogScale)
    return
