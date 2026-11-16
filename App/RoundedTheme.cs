using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace TechMaster
{
    internal static class RoundedOutline
    {
        public static GraphicsPath Create(RectangleF bounds, float radius)
        {
            float diameter = Math.Min(radius * 2, Math.Min(bounds.Width, bounds.Height));
            var path = new GraphicsPath();
            path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
            path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
            path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }
    }

    public sealed class RoundedCard : Panel
    {
        public Color SurfaceColor { get; set; }
        public Color BorderColor { get; set; }

        public RoundedCard()
        {
            SurfaceColor = Color.FromArgb(244, 248, 253);
            BorderColor = Color.FromArgb(218, 229, 242);
            DoubleBuffered = true;
            ResizeRedraw = true;
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            base.OnPaintBackground(e);
            if (Width < 2 || Height < 2) return;

            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var path = RoundedOutline.Create(new RectangleF(0.5f, 0.5f, Width - 1, Height - 1), 14f))
            using (var surface = new SolidBrush(SurfaceColor))
            using (var border = new Pen(BorderColor))
            {
                e.Graphics.FillPath(surface, path);
                e.Graphics.DrawPath(border, path);
            }
        }
    }

    public sealed class RoundedButton : Button
    {
        public RoundedButton()
        {
            DoubleBuffered = true;
            ResizeRedraw = true;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            if (Width < 2 || Height < 2) return;

            var card = Parent as RoundedCard;
            Color background = card != null ? card.SurfaceColor : (Parent == null ? SystemColors.Control : Parent.BackColor);
            e.Graphics.Clear(background);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;

            Color fill = BackColor;
            if (!Enabled)
                fill = Color.FromArgb(227, 234, 244);
            else if (ClientRectangle.Contains(PointToClient(Cursor.Position)))
                fill = FlatAppearance.MouseOverBackColor.IsEmpty ? ControlPaint.Light(BackColor, 0.12f) : FlatAppearance.MouseOverBackColor;

            using (var path = RoundedOutline.Create(new RectangleF(0.5f, 0.5f, Width - 1, Height - 1), Math.Min(12f, Height / 3f)))
            using (var surface = new SolidBrush(fill))
            {
                e.Graphics.FillPath(surface, path);
                if (Enabled && FlatAppearance.BorderSize > 0)
                {
                    using (var border = new Pen(FlatAppearance.BorderColor))
                        e.Graphics.DrawPath(border, path);
                }
            }

            var textBounds = Rectangle.Inflate(ClientRectangle, -7, -2);
            var flags = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine |
                        TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix;
            TextRenderer.DrawText(e.Graphics, Text, Font, textBounds, Enabled ? ForeColor : Color.FromArgb(90, 106, 128), flags);
            if (Focused && ShowFocusCues && Width > 14 && Height > 10)
                ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(ClientRectangle, -6, -4), ForeColor, fill);
        }

        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); Invalidate(); }
    }
}
