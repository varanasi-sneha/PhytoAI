const SUPABASE_URL = "https://eabarbrhjoptxagcnomy.supabase.co";
const SUPABASE_KEY = "sb_publishable_JPouxdPJhmiwdJ-_dlWXIg_pfMcsDUO";

/* Create Supabase client only once globally */
if (!window.supabaseClient) {
  window.supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: {
      // Store session in localStorage so it persists across page loads
      persistSession: true,
      autoRefreshToken: true,
    }
  });
}

document.addEventListener("DOMContentLoaded", async () => {

  const supabase = window.supabaseClient;

  const authBtn = document.getElementById("authBtn");
  const authModal = document.getElementById("authModal");
  const closeAuth = document.getElementById("closeAuth");

  const loginForm = document.getElementById("loginForm");
  const signupForm = document.getElementById("signupForm");

  const showSignup = document.getElementById("showSignup");
  const showLogin = document.getElementById("showLogin");

  const loginBtn = document.getElementById("loginSubmit");
  const signupBtn = document.getElementById("signupSubmit");

  if (!authBtn) return;

  /* ── Server Restart Detection ──────────────────────────────────────────
     When you restart Flask during dev, the old Supabase JWT is still
     sitting in localStorage. We compare a run_id the server generates
     each boot; if it changed, we sign out so you start fresh.
  */
  try {
    const req = await fetch("/api/status");
    if (req.ok) {
      const { run_id } = await req.json();
      const storedRunId = sessionStorage.getItem("phytoai_server_run_id");

      if (storedRunId && storedRunId !== run_id) {
        console.log("Server restart detected — clearing stale session.");
        await supabase.auth.signOut();
      }

      sessionStorage.setItem("phytoai_server_run_id", run_id);
    }
  } catch (err) {
    console.warn("Could not reach /api/status:", err.message);
  }

  /* ── Sync button label to current session ──────────────────────────── */
  function updateAuthBtn(session) {
    authBtn.innerText = session ? "Logout" : "Login/Signup🌱";
  }

  const { data: { session: initialSession } } = await supabase.auth.getSession();
  updateAuthBtn(initialSession);

  /* ── Live auth state listener ──────────────────────────────────────── */
  supabase.auth.onAuthStateChange((event, session) => {
    updateAuthBtn(session);
    if (event === "SIGNED_IN" && authModal) {
      authModal.style.display = "none";
    }
  });

  /* ── Auth button: logout if logged in, else show modal ────────────── */
  authBtn.onclick = async () => {
    const { data: { session } } = await supabase.auth.getSession();

    if (session) {
      const { error } = await supabase.auth.signOut();
      if (error) {
        alert("Logout error: " + error.message);
      } else {
        alert("Logged out successfully.");
      }
      return;
    }

    // Show login form
    if (loginForm) loginForm.style.display = "block";
    if (signupForm) signupForm.style.display = "none";
    if (authModal) authModal.style.display = "flex";
  };

  /* ── Close modal ───────────────────────────────────────────────────── */
  if (closeAuth) {
    closeAuth.onclick = () => authModal.style.display = "none";
  }

  // Also close if clicking the dark overlay behind the modal
  if (authModal) {
    authModal.addEventListener("click", (e) => {
      if (e.target === authModal) authModal.style.display = "none";
    });
  }

  /* ── Switch between Login / Signup forms ───────────────────────────── */
  if (showSignup) {
    showSignup.onclick = () => {
      loginForm.style.display = "none";
      signupForm.style.display = "block";
    };
  }

  if (showLogin) {
    showLogin.onclick = () => {
      signupForm.style.display = "none";
      loginForm.style.display = "block";
    };
  }

  /* ── LOGIN ─────────────────────────────────────────────────────────── */
  if (loginBtn) {
    loginBtn.addEventListener("click", async (e) => {
      e.preventDefault();

      const email = document.getElementById("loginEmail").value.trim();
      const password = document.getElementById("loginPassword").value;

      if (!email || !password) {
        alert("Please enter email and password.");
        return;
      }

      loginBtn.disabled = true;
      loginBtn.innerText = "Logging in...";

      try {
        const { data, error } = await supabase.auth.signInWithPassword({ email, password });

        if (error) {
          alert(error.message || "Login failed.");
        } else {
          // onAuthStateChange will close the modal automatically
        }
      } catch (err) {
        console.error(err);
        alert("Unexpected error during login.");
      }

      loginBtn.disabled = false;
      loginBtn.innerText = "Login";
    });
  }

  /* ── SIGNUP ────────────────────────────────────────────────────────── */
  if (signupBtn) {
    signupBtn.addEventListener("click", async (e) => {
      e.preventDefault();

      const name = document.getElementById("signupName").value.trim();
      const email = document.getElementById("signupEmail").value.trim();
      const password = document.getElementById("signupPassword").value;

      if (!name || !email || !password) {
        alert("Please fill in all fields.");
        return;
      }

      if (password.length < 6) {
        alert("Password must be at least 6 characters.");
        return;
      }

      signupBtn.disabled = true;
      signupBtn.innerText = "Creating account...";

      try {
        const { data, error } = await supabase.auth.signUp({
          email,
          password,
          options: {
            data: { full_name: name }
          }
        });

        if (error) {
          alert(error.message || "Signup failed.");
        } else if (data.user && data.user.identities && data.user.identities.length === 0) {
          // Supabase returns a fake user object if email already exists
          alert("An account with this email already exists. Please login.");
          signupForm.style.display = "none";
          loginForm.style.display = "block";
        } else {
          // Check if email confirmation is required
          if (!data.session) {
            alert("Account created! Please check your email to confirm your account, then login.");
          } else {
            alert("Account created and logged in!");
          }
          signupForm.style.display = "none";
          loginForm.style.display = "block";
        }
      } catch (err) {
        console.error(err);
        alert("Unexpected error during signup.");
      }

      signupBtn.disabled = false;
      signupBtn.innerText = "Sign Up";
    });
  }

});