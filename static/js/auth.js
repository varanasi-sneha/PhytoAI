const SUPABASE_URL = "https://eabarbrhjoptxagcnomy.supabase.co";
const SUPABASE_KEY = "sb_publishable_JPouxdPJhmiwdJ-_dlWXIg_pfMcsDUO";

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
window.supabaseClient = supabase; // Expose for other scripts

document.addEventListener("DOMContentLoaded", async () => {

    const authBtn = document.getElementById("authBtn");
    const authModal = document.getElementById("authModal");
    const closeAuth = document.getElementById("closeAuth");

    const loginForm = document.getElementById("loginForm");
    const signupForm = document.getElementById("signupForm");

    const showSignup = document.getElementById("showSignup");
    const showLogin = document.getElementById("showLogin");

    const loginBtn = document.getElementById("loginSubmit");
    const signupBtn = document.getElementById("signupSubmit");

    if(!authBtn) return;

    // Check initial session
    const { data: { session } } = await supabase.auth.getSession();
    if (session) {
        authBtn.innerText = "Logout";
    }

    // Auth state changes
    supabase.auth.onAuthStateChange((event, session) => {
        if (event === 'SIGNED_IN') {
            authBtn.innerText = "Logout";
            if (authModal) authModal.style.display = "none";
        } else if (event === 'SIGNED_OUT') {
            authBtn.innerText = "Login/Signup🌱";
        }
    });

    /* AUTH BUTTON */
    authBtn.onclick = async () => {
        const { data: { session } } = await window.supabaseClient.auth.getSession();
        
        if(session){
            const { error } = await window.supabaseClient.auth.signOut();
            if (error) {
                alert("Error logging out: " + error.message);
            } else {
                alert("Logged out successfully");
            }
            return;
        }

        loginForm.style.display="block";
        signupForm.style.display="none";
        authModal.style.display="block";
    };

    /* CLOSE MODAL */
    if(closeAuth){
        closeAuth.onclick = () => authModal.style.display="none";
    }

    /* SWITCH FORMS */
    if(showSignup){
        showSignup.onclick = () => {
            loginForm.style.display="none";
            signupForm.style.display="block";
        };
    }

    if(showLogin){
        showLogin.onclick = () => {
            signupForm.style.display="none";
            loginForm.style.display="block";
        };
    }

    /* LOGIN */
    if(loginBtn){
        loginBtn.addEventListener("click", async (e)=>{
            e.preventDefault();

            const email=document.getElementById("loginEmail").value;
            const password=document.getElementById("loginPassword").value;
            
            loginBtn.disabled = true;
            try{
                const { data, error } = await window.supabaseClient.auth.signInWithPassword({
                    email,
                    password
                });

                if(error){
                    alert(error.message || "Login failed");
                } else {
                    alert("Login successful!");
                }
            }catch(err){
                console.error(err);
                alert("Server error during login");
            } finally {
                loginBtn.disabled = false;
            }
        });
    }

    /* SIGNUP */
    if(signupBtn){
        signupBtn.addEventListener("click", async (e)=>{
            e.preventDefault();

            const name=document.getElementById("signupName").value;
            const email=document.getElementById("signupEmail").value;
            const password=document.getElementById("signupPassword").value;

            signupBtn.disabled = true;
            try{
                const { data, error } = await window.supabaseClient.auth.signUp({
                    email,
                    password,
                    options: {
                        data: {
                            full_name: name
                        }
                    }
                });

                if(error){
                    alert(error.message || "Signup failed");
                }else{
                    alert("Registration successful! Please login.");
                    signupForm.style.display="none";
                    loginForm.style.display="block";
                }
            }catch(err){
                console.error(err);
                alert("Server error during signup");
            } finally {
                signupBtn.disabled = false;
            }
        });
    }

});
