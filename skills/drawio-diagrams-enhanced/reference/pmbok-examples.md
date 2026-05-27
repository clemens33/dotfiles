# PMBOK Diagram Examples

Full XML examples for WBS, RACI Matrix, and Stakeholder Power-Interest Grid. Load on demand from the `drawio-diagrams-enhanced` skill when generating one of these specific diagram types.

## Creating PMP/PMBOK Diagrams

### Work Breakdown Structure (WBS) Example

```xml
<mxfile host="app.diagrams.net">
  <diagram id="WBS-1" name="Project WBS">
    <mxGraphModel dx="1434" dy="759" grid="1" gridSize="10" guides="1">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        
        <!-- Level 0: Project -->
        <mxCell id="2" value="Project Name" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#1ba1e2;strokeColor=#006EAF;fontColor=#ffffff;fontStyle=1;fontSize=14;" vertex="1" parent="1">
          <mxGeometry x="280" y="40" width="200" height="80" as="geometry"/>
        </mxCell>
        
        <!-- Level 1: Major Deliverables -->
        <mxCell id="3" value="Deliverable 1" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#60a917;strokeColor=#2D7600;fontColor=#ffffff;fontStyle=1;" vertex="1" parent="1">
          <mxGeometry x="40" y="160" width="160" height="60" as="geometry"/>
        </mxCell>
        
        <mxCell id="4" value="Deliverable 2" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#60a917;strokeColor=#2D7600;fontColor=#ffffff;fontStyle=1;" vertex="1" parent="1">
          <mxGeometry x="240" y="160" width="160" height="60" as="geometry"/>
        </mxCell>
        
        <mxCell id="5" value="Deliverable 3" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#60a917;strokeColor=#2D7600;fontColor=#ffffff;fontStyle=1;" vertex="1" parent="1">
          <mxGeometry x="440" y="160" width="160" height="60" as="geometry"/>
        </mxCell>
        
        <!-- Connectors -->
        <mxCell id="6" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=0.25;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;" edge="1" parent="1" source="2" target="3">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>
        
        <mxCell id="7" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;" edge="1" parent="1" source="2" target="4">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>
        
        <mxCell id="8" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=0.75;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;" edge="1" parent="1" source="2" target="5">
          <mxGeometry relative="1" as="geometry"/>
        </mxCell>
        
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

### RACI Matrix Example

```xml
<mxfile host="app.diagrams.net">
  <diagram id="RACI-1" name="RACI Matrix">
    <mxGraphModel dx="1434" dy="759" grid="1" gridSize="10" guides="1">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        
        <!-- Matrix Container -->
        <mxCell id="2" value="RACI Matrix" style="swimlane;html=1;startSize=40;fillColor=#f5f5f5;strokeColor=#666666;fontStyle=1;fontSize=14;" vertex="1" parent="1">
          <mxGeometry x="40" y="40" width="720" height="400" as="geometry"/>
        </mxCell>
        
        <!-- Header Row -->
        <mxCell id="3" value="Activities / Tasks" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#e1d5e7;strokeColor=#9673a6;fontStyle=1;" vertex="1" parent="2">
          <mxGeometry x="10" y="50" width="180" height="40" as="geometry"/>
        </mxCell>
        
        <mxCell id="4" value="Role A" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#e1d5e7;strokeColor=#9673a6;fontStyle=1;" vertex="1" parent="2">
          <mxGeometry x="200" y="50" width="120" height="40" as="geometry"/>
        </mxCell>
        
        <mxCell id="5" value="Role B" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#e1d5e7;strokeColor=#9673a6;fontStyle=1;" vertex="1" parent="2">
          <mxGeometry x="330" y="50" width="120" height="40" as="geometry"/>
        </mxCell>
        
        <!-- Task Rows with RACI Assignments -->
        <mxCell id="6" value="Task 1: Define Requirements" style="rounded=0;whiteSpace=wrap;html=1;align=left;spacingLeft=10;" vertex="1" parent="2">
          <mxGeometry x="10" y="100" width="180" height="50" as="geometry"/>
        </mxCell>
        
        <mxCell id="7" value="R" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;fontStyle=1;fontSize=16;" vertex="1" parent="2">
          <mxGeometry x="200" y="100" width="120" height="50" as="geometry"/>
        </mxCell>
        
        <mxCell id="8" value="A" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#dae8fc;strokeColor=#6c8ebf;fontStyle=1;fontSize=16;" vertex="1" parent="2">
          <mxGeometry x="330" y="100" width="120" height="50" as="geometry"/>
        </mxCell>
        
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

### Stakeholder Power-Interest Grid Example

```xml
<mxfile host="app.diagrams.net">
  <diagram id="Stakeholder-1" name="Stakeholder Map">
    <mxGraphModel dx="1434" dy="759" grid="1" gridSize="10" guides="1">
      <root>
        <mxCell id="0"/>
        <mxCell id="1" parent="0"/>
        
        <!-- Grid Background -->
        <!-- High Power, High Interest -->
        <mxCell id="2" value="Manage Closely&lt;br&gt;&lt;b&gt;(Key Players)&lt;/b&gt;" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#f8cecc;strokeColor=#b85450;verticalAlign=top;fontSize=12;fontStyle=0;" vertex="1" parent="1">
          <mxGeometry x="400" y="80" width="320" height="280" as="geometry"/>
        </mxCell>
        
        <!-- High Power, Low Interest -->
        <mxCell id="3" value="Keep Satisfied&lt;br&gt;&lt;b&gt;(Keep Informed)&lt;/b&gt;" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#fff2cc;strokeColor=#d6b656;verticalAlign=top;fontSize=12;fontStyle=0;" vertex="1" parent="1">
          <mxGeometry x="400" y="360" width="320" height="280" as="geometry"/>
        </mxCell>
        
        <!-- Low Power, High Interest -->
        <mxCell id="4" value="Keep Informed&lt;br&gt;&lt;b&gt;(Show Consideration)&lt;/b&gt;" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#ffe6cc;strokeColor=#d79b00;verticalAlign=top;fontSize=12;fontStyle=0;" vertex="1" parent="1">
          <mxGeometry x="80" y="80" width="320" height="280" as="geometry"/>
        </mxCell>
        
        <!-- Low Power, Low Interest -->
        <mxCell id="5" value="Monitor&lt;br&gt;&lt;b&gt;(Minimal Effort)&lt;/b&gt;" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#d5e8d4;strokeColor=#82b366;verticalAlign=top;fontSize=12;fontStyle=0;" vertex="1" parent="1">
          <mxGeometry x="80" y="360" width="320" height="280" as="geometry"/>
        </mxCell>
        
        <!-- Axis Labels -->
        <mxCell id="6" value="Interest" style="text;html=1;align=center;verticalAlign=middle;fontSize=14;fontStyle=1;rotation=90;" vertex="1" parent="1">
          <mxGeometry x="20" y="320" width="100" height="40" as="geometry"/>
        </mxCell>
        
        <mxCell id="7" value="Power / Influence" style="text;html=1;align=center;verticalAlign=middle;fontSize=14;fontStyle=1;" vertex="1" parent="1">
          <mxGeometry x="350" y="660" width="200" height="40" as="geometry"/>
        </mxCell>
        
        <!-- Sample Stakeholders -->
        <mxCell id="8" value="CEO" style="ellipse;whiteSpace=wrap;html=1;fillColor=#1ba1e2;strokeColor=#006EAF;fontColor=#ffffff;fontStyle=1;" vertex="1" parent="1">
          <mxGeometry x="520" y="150" width="80" height="60" as="geometry"/>
        </mxCell>
        
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```
