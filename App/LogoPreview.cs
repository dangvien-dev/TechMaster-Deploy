using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Xml;

namespace TechMaster
{
    // Converts local SVG artwork to a WPF drawing. Never hosts a browser or
    // resolves external references. Original logo files remain untouched.
    public sealed class LogoPreview
    {
        private readonly Dictionary<string, XmlElement> ids = new Dictionary<string, XmlElement>();
        private readonly Dictionary<string, string> classes = new Dictionary<string, string>();
        private static readonly Regex Numbers = new Regex(@"[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?");
        private static double Number(string value, double fallback)
        {
            if (String.IsNullOrWhiteSpace(value)) return fallback;
            Match match = Numbers.Match(value);
            if (!match.Success) throw new FormatException("Invalid SVG number.");
            double result = Double.Parse(match.Value, CultureInfo.InvariantCulture);
            if (Double.IsNaN(result) || Double.IsInfinity(result)) throw new FormatException("Invalid SVG number.");
            return result;
        }
        private static double[] Values(string value)
        {
            var result = new List<double>();
            foreach (Match match in Numbers.Matches(value)) result.Add(Double.Parse(match.Value, CultureInfo.InvariantCulture));
            return result.ToArray();
        }
        private static void Inline(Dictionary<string, string> style, string text)
        {
            foreach (string rule in text.Split(';')) {
                int separator = rule.IndexOf(':');
                if (separator > 0) style[rule.Substring(0, separator).Trim()] = rule.Substring(separator + 1).Trim();
            }
        }
        private Dictionary<string, string> Style(XmlElement node, Dictionary<string, string> parent)
        {
            var style = new Dictionary<string, string>(parent);
            style.Remove("opacity"); style.Remove("display"); style.Remove("transform");
            foreach (string key in new[] { "fill", "stroke", "stroke-width", "fill-rule", "fill-opacity", "stroke-opacity", "stroke-linecap", "stroke-linejoin", "opacity", "display" })
                if (node.HasAttribute(key)) style[key] = node.GetAttribute(key);
            foreach (string name in node.GetAttribute("class").Split(new[] { ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
                if (classes.ContainsKey(name)) Inline(style, classes[name]);
            Inline(style, node.GetAttribute("style"));
            return style;
        }
        private static string Get(Dictionary<string, string> style, string key, string fallback)
        { string value; return style.TryGetValue(key, out value) ? value : fallback; }
        private static Transform Transform(string text)
        {
            var transforms = new List<System.Windows.Media.Transform>();
            foreach (Match match in Regex.Matches(text, @"([A-Za-z]+)\s*\(([^)]*)\)")) {
                double[] n = Values(match.Groups[2].Value);
                switch (match.Groups[1].Value) {
                    case "matrix": if (n.Length != 6) throw new FormatException(); transforms.Add(new MatrixTransform(new Matrix(n[0], n[1], n[2], n[3], n[4], n[5]))); break;
                    case "translate": transforms.Add(new TranslateTransform(n[0], n.Length > 1 ? n[1] : 0)); break;
                    case "scale": transforms.Add(new ScaleTransform(n[0], n.Length > 1 ? n[1] : n[0])); break;
                    case "rotate": transforms.Add(new RotateTransform(n[0], n.Length > 2 ? n[1] : 0, n.Length > 2 ? n[2] : 0)); break;
                    case "skewX": transforms.Add(new SkewTransform(n[0], 0)); break;
                    case "skewY": transforms.Add(new SkewTransform(0, n[0])); break;
                    default: throw new NotSupportedException("Unsupported SVG transform.");
                }
            }
            var group = new TransformGroup();
            for (int i = transforms.Count - 1; i >= 0; i--) group.Children.Add(transforms[i]);
            return group;
        }
        private Brush Brush(string text, double opacity)
        {
            if (text == "none" || String.IsNullOrWhiteSpace(text)) return null;
            Brush brush;
            Match reference = Regex.Match(text, @"^url\(\s*#([^\s)]+)\s*\)$");
            if (reference.Success) {
                XmlElement gradient;
                if (!ids.TryGetValue(reference.Groups[1].Value, out gradient) || gradient.LocalName != "linearGradient") throw new NotSupportedException("Unsupported SVG paint.");
                if (gradient.GetAttribute("gradientUnits") == "userSpaceOnUse") throw new NotSupportedException("Absolute gradient requires a raster preview.");
                var linear = new LinearGradientBrush();
                Func<string, double, double> coordinate = delegate(string value, double fallback) { return Number(value, fallback) / (value.Contains("%") ? 100 : 1); };
                linear.StartPoint = new Point(coordinate(gradient.GetAttribute("x1"), 0), coordinate(gradient.GetAttribute("y1"), 0));
                linear.EndPoint = new Point(coordinate(gradient.GetAttribute("x2"), 1), coordinate(gradient.GetAttribute("y2"), 0));
                foreach (XmlNode child in gradient.ChildNodes) {
                    XmlElement stop = child as XmlElement; if (stop == null || stop.LocalName != "stop") continue;
                    var style = Style(stop, new Dictionary<string, string>());
                    string color = stop.GetAttribute("stop-color"); if (style.ContainsKey("stop-color")) color = style["stop-color"];
                    Color c = (Color)ColorConverter.ConvertFromString(String.IsNullOrEmpty(color) ? "black" : color);
                    c.A = (byte)(255 * Math.Max(0, Math.Min(1, Number(Get(style, "stop-opacity", stop.GetAttribute("stop-opacity")), 1))));
                    linear.GradientStops.Add(new GradientStop(c, coordinate(stop.GetAttribute("offset"), 0)));
                }
                if (linear.GradientStops.Count == 0) throw new NotSupportedException("Empty SVG gradient.");
                linear.RelativeTransform = Transform(gradient.GetAttribute("gradientTransform")); brush = linear;
            } else brush = (Brush)new BrushConverter().ConvertFromInvariantString(text);
            brush.Opacity = Math.Max(0, Math.Min(1, opacity)); return brush;
        }
        private Drawing Render(XmlElement node, Dictionary<string, string> parent, int depth)
        {
            if (depth > 32) throw new FormatException("SVG nesting is too deep.");
            string tag = node.LocalName;
            if (tag == "defs" || tag == "title" || tag == "desc" || tag == "metadata" || tag == "style" || tag == "namedview") return null;
            if (node.NamespaceURI != "http://www.w3.org/2000/svg" && node.NamespaceURI.Length != 0) return null;
            var style = Style(node, parent);
            if (Get(style, "display", "") == "none") return null;
            if (node.HasAttribute("clip-path") || node.HasAttribute("mask") || node.HasAttribute("filter") || style.ContainsKey("clip-path") || style.ContainsKey("mask") || style.ContainsKey("filter")) throw new NotSupportedException("SVG effects require a raster preview.");
            var group = new DrawingGroup(); group.Transform = Transform(node.GetAttribute("transform"));
            group.Opacity = Math.Max(0, Math.Min(1, Number(Get(style, "opacity", "1"), 1)));
            if (tag == "svg" || tag == "g" || tag == "symbol") {
                foreach (XmlNode child in node.ChildNodes) {
                    XmlElement element = child as XmlElement; if (element == null) continue;
                    Drawing drawing = Render(element, style, depth + 1); if (drawing != null) group.Children.Add(drawing);
                }
            } else if (tag == "use") {
                string href = node.GetAttribute("href"); if (href.Length == 0) href = node.GetAttribute("href", "http://www.w3.org/1999/xlink");
                XmlElement target;
                if (!href.StartsWith("#") || !ids.TryGetValue(href.Substring(1), out target)) throw new NotSupportedException("External SVG references are not loaded.");
                var translated = new DrawingGroup(); translated.Transform = new TranslateTransform(Number(node.GetAttribute("x"), 0), Number(node.GetAttribute("y"), 0));
                Drawing used = Render(target, style, depth + 1); if (used != null) translated.Children.Add(used); group.Children.Add(translated);
            } else if (tag == "image") {
                string href = node.GetAttribute("href"); if (href.Length == 0) href = node.GetAttribute("href", "http://www.w3.org/1999/xlink");
                Match data = Regex.Match(href, @"^data:image/(?:png|jpeg|jpg);base64,([A-Za-z0-9+/=\s]+)$");
                if (!data.Success) throw new NotSupportedException("Only embedded raster images are previewed.");
                BitmapImage image;
                using (var memory = new MemoryStream(Convert.FromBase64String(data.Groups[1].Value))) image = Bitmap(memory);
                group.Children.Add(new ImageDrawing(image, new Rect(Number(node.GetAttribute("x"), 0), Number(node.GetAttribute("y"), 0), Number(node.GetAttribute("width"), image.Width), Number(node.GetAttribute("height"), image.Height))));
            } else {
                double x = Number(node.GetAttribute("x"), 0), y = Number(node.GetAttribute("y"), 0);
                Geometry shape;
                switch (tag) {
                    case "path": if (String.IsNullOrWhiteSpace(node.GetAttribute("d"))) return null; shape = Geometry.Parse((Get(style, "fill-rule", "nonzero") == "evenodd" ? "F0 " : "F1 ") + node.GetAttribute("d")); break;
                    case "rect": shape = new RectangleGeometry(new Rect(x, y, Number(node.GetAttribute("width"), 0), Number(node.GetAttribute("height"), 0)), Number(node.GetAttribute("rx"), Number(node.GetAttribute("ry"), 0)), Number(node.GetAttribute("ry"), Number(node.GetAttribute("rx"), 0))); break;
                    case "circle": case "ellipse": shape = new EllipseGeometry(new Point(Number(node.GetAttribute("cx"), 0), Number(node.GetAttribute("cy"), 0)), Number(node.GetAttribute(tag == "circle" ? "r" : "rx"), 0), Number(node.GetAttribute(tag == "circle" ? "r" : "ry"), 0)); break;
                    case "line": shape = new LineGeometry(new Point(Number(node.GetAttribute("x1"), 0), Number(node.GetAttribute("y1"), 0)), new Point(Number(node.GetAttribute("x2"), 0), Number(node.GetAttribute("y2"), 0))); break;
                    case "polygon": case "polyline":
                        double[] points = Values(node.GetAttribute("points")); if (points.Length < 4 || points.Length % 2 != 0) throw new FormatException("Invalid SVG points.");
                        var polygon = new StreamGeometry(); polygon.FillRule = Get(style, "fill-rule", "nonzero") == "evenodd" ? FillRule.EvenOdd : FillRule.Nonzero;
                        using (StreamGeometryContext context = polygon.Open()) { context.BeginFigure(new Point(points[0], points[1]), true, tag == "polygon"); for (int i = 2; i < points.Length; i += 2) context.LineTo(new Point(points[i], points[i + 1]), true, false); } shape = polygon; break;
                    default: throw new NotSupportedException("Unsupported SVG element: " + tag);
                }
                Brush fill = Brush(Get(style, "fill", "black"), Number(Get(style, "fill-opacity", "1"), 1));
                Brush stroke = Brush(Get(style, "stroke", "none"), Number(Get(style, "stroke-opacity", "1"), 1));
                Pen pen = stroke == null ? null : new Pen(stroke, Number(Get(style, "stroke-width", "1"), 1));
                if (pen != null) {
                    string cap = Get(style, "stroke-linecap", "butt"); pen.StartLineCap = pen.EndLineCap = cap == "round" ? PenLineCap.Round : cap == "square" ? PenLineCap.Square : PenLineCap.Flat;
                    string join = Get(style, "stroke-linejoin", "miter"); pen.LineJoin = join == "round" ? PenLineJoin.Round : join == "bevel" ? PenLineJoin.Bevel : PenLineJoin.Miter; pen.MiterLimit = 4;
                }
                group.Children.Add(new GeometryDrawing(tag == "line" ? null : fill, pen, shape));
            }
            return group;
        }
        private static BitmapImage Bitmap(Stream stream)
        {
            var bitmap = new BitmapImage(); bitmap.BeginInit(); bitmap.CacheOption = BitmapCacheOption.OnLoad; bitmap.StreamSource = stream; bitmap.EndInit(); bitmap.Freeze(); return bitmap;
        }
        public static ImageSource Load(string path)
        {
            if (!String.Equals(Path.GetExtension(path), ".svg", StringComparison.OrdinalIgnoreCase)) {
                using (var stream = File.OpenRead(path)) return Bitmap(stream);
            }
            if (new FileInfo(path).Length > 4 * 1024 * 1024) throw new NotSupportedException("SVG is too large for an inline preview.");
            var document = new XmlDocument(); document.XmlResolver = null;
            using (var reader = XmlReader.Create(path, new XmlReaderSettings { DtdProcessing = DtdProcessing.Ignore, XmlResolver = null, MaxCharactersInDocument = 4 * 1024 * 1024 })) document.Load(reader);
            XmlElement root = document.DocumentElement;
            if (root == null || root.LocalName != "svg") throw new FormatException("Not an SVG document.");
            var renderer = new LogoPreview();
            foreach (XmlElement element in document.GetElementsByTagName("*")) {
                if (element.HasAttribute("id")) renderer.ids[element.GetAttribute("id")] = element;
                if (element.LocalName == "style") foreach (Match rule in Regex.Matches(element.InnerText, @"\.([A-Za-z_][\w-]*)\s*\{([^}]+)\}")) renderer.classes[rule.Groups[1].Value] = rule.Groups[2].Value;
            }
            double[] view = Values(root.GetAttribute("viewBox"));
            Rect bounds = view.Length == 4 ? new Rect(view[0], view[1], view[2], view[3]) : new Rect(0, 0, Number(root.GetAttribute("width"), 256), Number(root.GetAttribute("height"), 256));
            if (bounds.Width <= 0 || bounds.Height <= 0) throw new FormatException("Empty SVG viewport.");
            var drawing = new DrawingGroup(); drawing.ClipGeometry = new RectangleGeometry(bounds);
            drawing.Children.Add(new GeometryDrawing(Brushes.Transparent, null, new RectangleGeometry(bounds)));
            Drawing content = renderer.Render(root, new Dictionary<string, string>(), 0); if (content != null) drawing.Children.Add(content);
            var imageSource = new DrawingImage(drawing); imageSource.Freeze(); return imageSource;
        }
    }
}
