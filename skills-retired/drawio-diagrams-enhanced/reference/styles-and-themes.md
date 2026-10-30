# Styles and Themes

Color schemes and connector style strings. Load on demand from the `drawio-diagrams-enhanced` skill when authoring complex diagrams; the main skill keeps the basic shape style strings for the most common use cases.

## Color Schemes

### Professional Blue Theme (Default)
- **Primary**: `fillColor=#dae8fc;strokeColor=#6c8ebf;`
- **Secondary**: `fillColor=#b1ddf0;strokeColor=#10739e;`
- **Accent**: `fillColor=#f8cecc;strokeColor=#b85450;`

### Green/Natural Theme
- **Primary**: `fillColor=#d5e8d4;strokeColor=#82b366;`
- **Secondary**: `fillColor=#fff2cc;strokeColor=#d6b656;`
- **Accent**: `fillColor=#e1d5e7;strokeColor=#9673a6;`

### Corporate/Neutral Theme
- **Primary**: `fillColor=#f5f5f5;strokeColor=#666666;`
- **Secondary**: `fillColor=#e1d5e7;strokeColor=#9673a6;`
- **Highlight**: `fillColor=#ffe6cc;strokeColor=#d79b00;`

### PMP Risk Matrix Colors
- **Critical**: `fillColor=#8B0000;strokeColor=#600000;fontColor=#ffffff;` (Dark Red)
- **High**: `fillColor=#FF0000;strokeColor=#CC0000;fontColor=#ffffff;` (Red)
- **Medium**: `fillColor=#FFA500;strokeColor=#CC8400;fontColor=#000000;` (Orange)
- **Low**: `fillColor=#FFFF00;strokeColor=#CCCC00;fontColor=#000000;` (Yellow)
- **Very Low**: `fillColor=#90EE90;strokeColor=#66AA66;fontColor=#000000;` (Light Green)

## Connector Styles

### Basic Connector
```
edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;
```

### Straight Connector
```
rounded=0;html=1;jettySize=auto;orthogonalLoop=1;
```

### Curved Connector
```
curved=1;rounded=1;html=1;jettySize=auto;orthogonalLoop=1;
```

### With Arrow
```
edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;endArrow=classic;endFill=1;
```

### Dashed Line (for dependencies)
```
edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;dashed=1;dashPattern=5 5;
```

### Thick Line (for critical path)
```
edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeWidth=3;strokeColor=#b85450;
```
