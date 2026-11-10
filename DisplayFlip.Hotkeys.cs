using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace DisplayFlip
{
    public sealed class HotkeyWindow : NativeWindow, IDisposable
    {
        private readonly List<int> registered = new List<int>();
        private bool dispatching;
        public event Action<int> Pressed;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint key);
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr window, int id);

        public HotkeyWindow()
        {
            CreateHandle(new CreateParams { Caption = "DisplayFlip.Hotkeys" });
        }

        public void Register(int id, uint modifiers, uint key)
        {
            if (!RegisterHotKey(Handle, id, modifiers | 0x4000, key))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            registered.Add(id);
        }

        protected override void WndProc(ref Message message)
        {
            if (message.Msg == 0x0312 && !dispatching)
            {
                var handler = Pressed;
                if (handler != null)
                {
                    dispatching = true;
                    try { handler(message.WParam.ToInt32()); }
                    finally { dispatching = false; }
                }
                return;
            }
            base.WndProc(ref message);
        }

        public void Dispose()
        {
            foreach (int id in registered)
                UnregisterHotKey(Handle, id);
            registered.Clear();
            if (Handle != IntPtr.Zero)
                DestroyHandle();
        }
    }
}