/*
 * HDSdlCompat.h -- the small subset of SDL2 that hDesktop uses, implemented
 * on Vitruvian's native kits: a borderless floating BWindow holding a
 * BGLView, plus a BApplication run on its own thread.
 *
 * Vitruvian has no SDL video backend that talks to app_server (SDL would open
 * a raw DRM/KMS window instead), so hDesktop's SDL window never became a real
 * window and had no app_server connection. This header keeps the dock's code
 * unchanged while giving it a real window.
 *
 * Threading: the render (main) thread takes the GL lock once, in
 * SDL_GL_CreateContext(), and keeps it for its lifetime. The window thread
 * never takes the GL lock: BGLView::FrameResized() does, which would
 * deadlock against the main thread's later BWindow::Lock() calls, so
 * HDGLView overrides it and the main thread applies the resize itself.
 */
#ifndef HD_SDL_COMPAT_H
#define HD_SDL_COMPAT_H

#include <deque>
#include <string.h>

#include <Application.h>
#include <Autolock.h>
#include <GL/gl.h>
#include <GL/glext.h>
#include <GLView.h>
#include <Locker.h>
#include <OS.h>
#include <Screen.h>
#include <View.h>
#include <Window.h>

typedef uint8_t  Uint8;
typedef uint32_t Uint32;
typedef uint64_t Uint64;

enum {
	SDL_QUIT = 0x100,
	SDL_WINDOWEVENT = 0x200,
	SDL_KEYDOWN = 0x300,
	SDL_MOUSEMOTION = 0x400,
	SDL_MOUSEBUTTONDOWN,
	SDL_MOUSEBUTTONUP,
	SDL_MOUSEWHEEL,
	SDL_USEREVENT = 0x8000
};

enum {
	SDL_WINDOWEVENT_FOCUS_GAINED = 1,
	SDL_WINDOWEVENT_TAKE_FOCUS
};

#define SDL_BUTTON_LEFT		1
#define SDL_BUTTON_MIDDLE	2
#define SDL_BUTTON_RIGHT	3
#define SDL_BUTTON(x)		(1 << ((x) - 1))
#define SDLK_ESCAPE			27

#define SDL_INIT_VIDEO		1
#define SDL_WINDOW_OPENGL	1
#define SDL_WINDOW_BORDERLESS	2
#define SDL_GL_CONTEXT_MAJOR_VERSION	1
#define SDL_GL_CONTEXT_MINOR_VERSION	2
#define SDL_GL_DOUBLEBUFFER	3

struct SDL_Event {
	Uint32 type;
	struct { int event; } window;
	struct { Uint8 button; } button;
	struct { int y; } wheel;
	struct { struct { int sym; } keysym; } key;
};

struct SDL_DisplayMode {
	int w, h;
};

#define SDL_zero(x) memset(&(x), 0, sizeof(x))

class HDWindow;
typedef HDWindow SDL_Window;
typedef void* SDL_GLContext;

namespace hdvos {

static const char* const kSignature = "application/x-vnd.hdesktop";

struct State {
	BLocker			lock;
	std::deque<SDL_Event> queue;
	sem_id			eventSem;
	sem_id			readySem;
	bool			appFailed;
	thread_id		appThread;
	bool			allowQuit;
	int32			mouseX, mouseY;
	uint32			buttons;		// SDL button mask
	bool			mouseInside;
	// Latest size seen by the window thread, applied by the main thread.
	BLocker			resizeLock;
	float			pendingW, pendingH;
	bool			resizePending;
	bigtime_t		startTime;
	HDWindow*		window;

	State()
		: lock("hd events"), eventSem(-1), readySem(-1), appFailed(false), appThread(-1),
		allowQuit(false), mouseX(0), mouseY(0), buttons(0),
		mouseInside(false), resizeLock("hd resize"), pendingW(0),
		pendingH(0), resizePending(false), startTime(0), window(NULL)
	{
	}
};

inline State& S()
{
	static State state;
	return state;
}

inline void Push(const SDL_Event& e)
{
	State& s = S();
	{
		BAutolock _(s.lock);
		s.queue.push_back(e);
	}
	release_sem(s.eventSem);
}

inline void PushSimple(Uint32 type)
{
	SDL_Event e;
	SDL_zero(e);
	e.type = type;
	Push(e);
}

inline bool Pop(SDL_Event* out)
{
	State& s = S();
	BAutolock _(s.lock);
	if (s.queue.empty())
		return false;
	*out = s.queue.front();
	s.queue.pop_front();
	return true;
}

}	// namespace hdvos


class HDApp : public BApplication {
public:
	HDApp() : BApplication(hdvos::kSignature) {}

	virtual void ReadyToRun()
	{
		release_sem(hdvos::S().readySem);
	}

	virtual bool QuitRequested()
	{
		if (hdvos::S().allowQuit)
			return true;
		// Let the main loop shut the dock down in an orderly way.
		hdvos::PushSimple(SDL_QUIT);
		return false;
	}
};


class HDGLView : public BGLView {
public:
	HDGLView(BRect frame)
		:
		BGLView(frame, "hdesktop_gl", B_FOLLOW_ALL, B_WILL_DRAW,
			BGL_RGB | BGL_ALPHA | BGL_DOUBLE),
		fWheelAccum(0)
	{
	}

	// Not BGLView's version: that takes the GL lock, which the main thread
	// holds. Record the size; the main thread applies it (see
	// HD_ApplyPendingResize).
	virtual void FrameResized(float width, float height)
	{
		hdvos::State& s = hdvos::S();
		BAutolock _(s.resizeLock);
		s.pendingW = width;
		s.pendingH = height;
		s.resizePending = true;
	}

	// Draw() is BGLView's own: the renderer shows the last frame the render
	// thread produced (the surfaceless renderer blits its bitmap here).

	virtual void MouseMoved(BPoint where, uint32 code, const BMessage*)
	{
		hdvos::State& s = hdvos::S();
		s.mouseX = (int32)where.x;
		s.mouseY = (int32)where.y;
		s.mouseInside = (code != B_EXITED_VIEW && code != B_OUTSIDE_VIEW);
		SDL_Event e;
		SDL_zero(e);
		e.type = SDL_MOUSEMOTION;
		hdvos::Push(e);
	}

	virtual void MouseDown(BPoint where)
	{
		hdvos::State& s = hdvos::S();
		s.mouseX = (int32)where.x;
		s.mouseY = (int32)where.y;
		uint32 now = _SdlButtons(Window()->CurrentMessage());
		uint32 added = now & ~s.buttons;
		s.buttons = now;
		SetMouseEventMask(B_POINTER_EVENTS, B_NO_POINTER_HISTORY);
		for (int b = SDL_BUTTON_LEFT; b <= SDL_BUTTON_RIGHT; b++) {
			if (added & SDL_BUTTON(b))
				_PushButton(SDL_MOUSEBUTTONDOWN, b);
		}
	}

	virtual void MouseUp(BPoint where)
	{
		hdvos::State& s = hdvos::S();
		s.mouseX = (int32)where.x;
		s.mouseY = (int32)where.y;
		// B_MOUSE_UP carries no button mask: everything pressed is released.
		uint32 released = s.buttons;
		s.buttons = 0;
		for (int b = SDL_BUTTON_LEFT; b <= SDL_BUTTON_RIGHT; b++) {
			if (released & SDL_BUTTON(b))
				_PushButton(SDL_MOUSEBUTTONUP, b);
		}
	}

	virtual void MessageReceived(BMessage* message)
	{
		if (message->what == B_MOUSE_WHEEL_CHANGED) {
			float dy = 0;
			if (message->FindFloat("be:wheel_delta_y", &dy) == B_OK && dy != 0) {
				SDL_Event e;
				SDL_zero(e);
				e.type = SDL_MOUSEWHEEL;
				e.wheel.y = dy < 0 ? 1 : -1;	// SDL: positive = away from user
				hdvos::Push(e);
			}
			return;
		}
		BGLView::MessageReceived(message);
	}

private:
	static uint32 _SdlButtons(BMessage* message)
	{
		int32 buttons = 0;
		if (message != NULL)
			message->FindInt32("buttons", &buttons);
		uint32 mask = 0;
		if (buttons & B_PRIMARY_MOUSE_BUTTON)
			mask |= SDL_BUTTON(SDL_BUTTON_LEFT);
		if (buttons & B_TERTIARY_MOUSE_BUTTON)
			mask |= SDL_BUTTON(SDL_BUTTON_MIDDLE);
		if (buttons & B_SECONDARY_MOUSE_BUTTON)
			mask |= SDL_BUTTON(SDL_BUTTON_RIGHT);
		return mask;
	}

	static void _PushButton(Uint32 type, int button)
	{
		SDL_Event e;
		SDL_zero(e);
		e.type = type;
		e.button.button = (Uint8)button;
		hdvos::Push(e);
	}

	int fWheelAccum;
};


// A borderless dock window that floats over everything on every workspace.
class HDWindow : public BWindow {
public:
	HDWindow(BRect frame)
		:
		BWindow(frame, "hdesktop", B_NO_BORDER_WINDOW_LOOK,
			B_FLOATING_ALL_WINDOW_FEEL,
			B_NOT_RESIZABLE | B_NOT_ZOOMABLE | B_NOT_CLOSABLE
				| B_NOT_MINIMIZABLE | B_AVOID_FOCUS | B_ASYNCHRONOUS_CONTROLS,
			B_ALL_WORKSPACES),
		fView(new HDGLView(Bounds()))
	{
		AddChild(fView);
	}

	virtual bool QuitRequested()
	{
		if (hdvos::S().allowQuit)
			return true;
		hdvos::PushSimple(SDL_QUIT);
		return false;
	}

	virtual void WindowActivated(bool active)
	{
		if (active) {
			SDL_Event e;
			SDL_zero(e);
			e.type = SDL_WINDOWEVENT;
			e.window.event = SDL_WINDOWEVENT_FOCUS_GAINED;
			hdvos::Push(e);
		}
	}

	HDGLView* GLView() { return fView; }

private:
	HDGLView* fView;
};


// A BLooper is locked by the thread that constructs it, and Run() must be
// called from that same thread: build the application here, not in main.
inline int32 HD_AppThread(void*)
{
	hdvos::State& state = hdvos::S();
	HDApp* app = new HDApp();
	if (app->InitCheck() != B_OK) {
		state.appFailed = true;
		release_sem(state.readySem);
		delete app;
		return -1;
	}
	app->Run();
	delete app;
	return 0;
}


inline int SDL_Init(Uint32)
{
	hdvos::State& s = hdvos::S();
	s.eventSem = create_sem(0, "hd events");
	s.readySem = create_sem(0, "hd app ready");
	s.startTime = system_time();
	s.appThread = spawn_thread(HD_AppThread, "hdesktop app", B_NORMAL_PRIORITY,
		NULL);
	if (s.appThread < 0)
		return -1;
	resume_thread(s.appThread);
	// Wait for the looper to run before any window is created.
	if (acquire_sem_etc(s.readySem, 1, B_RELATIVE_TIMEOUT, 10000000) != B_OK
			|| s.appFailed)
		return -1;
	return 0;
}

inline const char* SDL_GetError() { return "native window layer failure"; }
inline void SDL_GL_SetAttribute(int, int) {}
inline int SDL_GL_SetSwapInterval(int) { return 0; }

inline int SDL_GetCurrentDisplayMode(int, SDL_DisplayMode* mode)
{
	BScreen screen(B_MAIN_SCREEN_ID);
	if (!screen.IsValid())
		return -1;
	BRect frame = screen.Frame();
	mode->w = (int)frame.Width() + 1;
	mode->h = (int)frame.Height() + 1;
	return 0;
}

inline SDL_Window* SDL_CreateWindow(const char*, int x, int y, int w, int h,
	Uint32)
{
	HDWindow* window = new HDWindow(BRect(x, y, x + w - 1, y + h - 1));
	window->Show();
	hdvos::S().window = window;
	return window;
}

// Takes the GL lock for the calling (render) thread and keeps it.
inline SDL_GLContext SDL_GL_CreateContext(SDL_Window* window)
{
	window->GLView()->LockGL();
	return window->GLView();
}

// The window thread only records a resize; apply it from the render thread,
// which holds the GL lock, so the renderer is resized without a second lock.
inline void HD_ApplyPendingResize(SDL_Window* window)
{
	hdvos::State& s = hdvos::S();
	float w, h;
	{
		BAutolock _(s.resizeLock);
		if (!s.resizePending)
			return;
		s.resizePending = false;
		w = s.pendingW;
		h = s.pendingH;
	}
	HDGLView* view = window->GLView();
	view->BGLView::FrameResized(w, h);
	// The renderer's resize leaves no GL context current on this thread;
	// take it again (and its framebuffer binding).
	view->UnlockGL();
	view->LockGL();
}

inline void SDL_GL_SwapWindow(SDL_Window* window)
{
	HD_ApplyPendingResize(window);
	window->GLView()->SwapBuffers(true);
}

inline void SDL_SetWindowSize(SDL_Window* window, int w, int h)
{
	if (window->Lock()) {
		window->ResizeTo(w - 1, h - 1);
		window->Unlock();
	}
}

inline void SDL_SetWindowPosition(SDL_Window* window, int x, int y)
{
	if (window->Lock()) {
		window->MoveTo(x, y);
		window->Unlock();
	}
}

inline void SDL_GetWindowPosition(SDL_Window* window, int* x, int* y)
{
	if (window->Lock()) {
		BRect frame = window->Frame();
		*x = (int)frame.left;
		*y = (int)frame.top;
		window->Unlock();
	}
}

inline SDL_Window* SDL_GetMouseFocus() { return hdvos::S().window; }

inline Uint32 SDL_GetMouseState(int* x, int* y)
{
	hdvos::State& s = hdvos::S();
	if (x != NULL)
		*x = s.mouseX;
	if (y != NULL)
		*y = s.mouseY;
	return s.buttons;
}

inline Uint32 SDL_GetTicks()
{
	return (Uint32)((system_time() - hdvos::S().startTime) / 1000);
}

inline Uint64 SDL_GetPerformanceCounter() { return (Uint64)system_time(); }
inline Uint64 SDL_GetPerformanceFrequency() { return 1000000; }

inline int SDL_PushEvent(SDL_Event* event)
{
	hdvos::Push(*event);
	return 1;
}

inline int SDL_PollEvent(SDL_Event* event)
{
	hdvos::State& s = hdvos::S();
	if (s.window != NULL)
		HD_ApplyPendingResize(s.window);
	if (acquire_sem_etc(s.eventSem, 1, B_RELATIVE_TIMEOUT, 0) != B_OK)
		return 0;
	return hdvos::Pop(event) ? 1 : 0;
}

inline int SDL_WaitEventTimeout(SDL_Event* event, int timeoutMs)
{
	hdvos::State& s = hdvos::S();
	if (s.window != NULL)
		HD_ApplyPendingResize(s.window);
	if (acquire_sem_etc(s.eventSem, 1, B_RELATIVE_TIMEOUT,
			(bigtime_t)timeoutMs * 1000) != B_OK)
		return 0;
	return hdvos::Pop(event) ? 1 : 0;
}

inline void SDL_GL_DeleteContext(SDL_GLContext context)
{
	if (context != NULL)
		static_cast<HDGLView*>(context)->UnlockGL();
}

inline void SDL_DestroyWindow(SDL_Window* window)
{
	hdvos::S().allowQuit = true;
	if (window->Lock())
		window->Quit();
}

inline void SDL_Quit()
{
	hdvos::State& s = hdvos::S();
	s.allowQuit = true;
	if (be_app != NULL && s.appThread >= 0) {
		be_app->PostMessage(B_QUIT_REQUESTED);
		status_t result;
		wait_for_thread(s.appThread, &result);
		s.appThread = -1;
	}
}

#endif	// HD_SDL_COMPAT_H
