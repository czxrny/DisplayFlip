using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace DisplayFlip
{
    public sealed class MonitorForm : Form
    {
        public Panel Screen { get; private set; }

        [DllImport("user32.dll")]
        private static extern bool ReleaseCapture();
        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam);

        public MonitorForm()
        {
            FormBorderStyle = FormBorderStyle.None;
            TopMost = true;
            BackColor = Color.FromArgb(221, 198, 163);
            
            DoubleBuffered = true;
            AutoScaleMode = AutoScaleMode.None;
            ClientSize = new Size(740, 780);
            Screen = new Panel { BackColor = Color.FromArgb(6, 59, 65) };
            Controls.Add(Screen);
            Button close = new Button
            {
                Text = "X", Size = new Size(26, 24), FlatStyle = FlatStyle.Flat,
                BackColor = Color.FromArgb(230, 208, 173), ForeColor = Color.FromArgb(76, 52, 35),
                Font = new Font("Segoe UI", 14), TabStop = false,
                Anchor = AnchorStyles.Top | AnchorStyles.Right, AccessibleName = "Close settings"
            };
            close.FlatAppearance.BorderSize = 0;
            close.Location = new Point(ClientSize.Width - 65, 24);
            close.Click += delegate { Close(); };
            close.DialogResult = DialogResult.Cancel;
            CancelButton = close;
            Controls.Add(close);
            MouseDown += delegate(object sender, MouseEventArgs args)
            {
                if (args.Button == MouseButtons.Left)
                {
                    ReleaseCapture();
                    SendMessage(Handle, 0xA1, new IntPtr(2), IntPtr.Zero);
                }
            };
            Resize += delegate { LayoutScreen(); };
            LayoutScreen();
        }

        private static GraphicsPath Rounded(Rectangle bounds, int radius)
        {
            GraphicsPath path = new GraphicsPath();
            int diameter = radius * 2;
            path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
            path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
            path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }

        private void LayoutScreen()
        {
            if (Screen == null) return;
            Screen.Bounds = new Rectangle(57, 65, ClientSize.Width - 114, ClientSize.Height - 230);
            Region previous = Screen.Region;
            using (GraphicsPath path = Rounded(new Rectangle(0, 0, Screen.Width, Screen.Height), 20))
                Screen.Region = new Region(path);
            if (previous != null) previous.Dispose();
            // Clip the window to its silhouette instead of color-key transparency,
            // which leaves colored fringes around antialiased edges.
            Region oldRegion = Region;
            using (GraphicsPath body = Rounded(new Rectangle(11, 9, ClientSize.Width - 22, ClientSize.Height - 110), 34))
            using (GraphicsPath neck = Rounded(new Rectangle(ClientSize.Width / 2 - 155, ClientSize.Height - 136, 310, 102), 12))
            using (GraphicsPath foot = Rounded(new Rectangle(ClientSize.Width / 2 - 253, ClientSize.Height - 66, 506, 52), 16))
            {
                Region shape = new Region(body);
                shape.Union(neck);
                shape.Union(foot);
                Region = shape;
            }
            if (oldRegion != null) oldRegion.Dispose();
            Invalidate();
        }

        protected override void OnPaint(PaintEventArgs args)
        {
            base.OnPaint(args);
            Graphics graphics = args.Graphics;
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            int width = ClientSize.Width;
            int height = ClientSize.Height;
            using (SolidBrush shadow = new SolidBrush(Color.FromArgb(145, 119, 86)))
            using (SolidBrush beige = new SolidBrush(Color.FromArgb(204, 176, 139)))
            using (GraphicsPath neck = Rounded(new Rectangle(width / 2 - 155, height - 136, 310, 102), 12))
            using (GraphicsPath foot = Rounded(new Rectangle(width / 2 - 250, height - 63, 500, 46), 15))
            {
                graphics.FillPath(shadow, neck);
                graphics.FillPath(beige, foot);
                using (Pen edge = new Pen(Color.FromArgb(159, 132, 97), 4)) graphics.DrawPath(edge, foot);
            }
            Rectangle body = new Rectangle(14, 12, width - 28, height - 116);
            using (GraphicsPath bezel = Rounded(body, 32))
            using (LinearGradientBrush fill = new LinearGradientBrush(body, Color.FromArgb(255, 240, 213), Color.FromArgb(194, 164, 124), 60f))
            using (Pen outline = new Pen(Color.FromArgb(169, 140, 103), 4))
            {
                graphics.FillPath(fill, bezel);
                graphics.DrawPath(outline, bezel);
            }
            Rectangle rim = new Rectangle(Screen.Left - 8, Screen.Top - 8, Screen.Width + 16, Screen.Height + 16);
            using (GraphicsPath path = Rounded(rim, 25))
            using (SolidBrush brush = new SolidBrush(Color.FromArgb(139, 115, 85))) graphics.FillPath(brush, path);
            int chin = Screen.Bottom + 24;
            using (SolidBrush badge = new SolidBrush(Color.FromArgb(57, 39, 28))) graphics.FillRectangle(badge, 46, chin, 37, 18);
            using (SolidBrush light = new SolidBrush(Color.FromArgb(142, 225, 66))) graphics.FillRectangle(light, 52, chin + 5, 25, 8);
            using (Font font = new Font("Segoe UI Semibold", 9))
            using (SolidBrush ink = new SolidBrush(Color.FromArgb(92, 65, 43)))
            {
                graphics.DrawString("DISPLAYFLIP", font, ink, 96, chin);
                for (int index = 0; index < 3; index++)
                    graphics.FillRectangle(ink, width - 105 + index * 16, chin - 2, 5, 23);
            }
        }
    }
}
