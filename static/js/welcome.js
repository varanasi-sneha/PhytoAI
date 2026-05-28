document.addEventListener('DOMContentLoaded', () => {
    
    const getStartedBtn = document.getElementById('btn-get-started');
    const authBtn = document.getElementById('btn-auth');

    // Go to homepage
    getStartedBtn.addEventListener('click', () => {
        window.location.href = '/homepage';
    });

    // Show login popup (NOT redirect)
    authBtn.addEventListener('click', () => {
        document.getElementById('authModal').style.display = 'flex';
    });
});