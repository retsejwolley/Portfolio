// Get all buttons and frames
const buttons = document.querySelectorAll('.btn');
const frames = document.querySelectorAll('.frame');

// Add click event to each button
buttons.forEach(button => {
    button.addEventListener('click', () => {
        const frameId = button.dataset.frame;
        if (!frameId) return; // If no frame ID, do nothing

        // Remove active class from all buttons and frames
        buttons.forEach(btn => btn.classList.remove('active'));
        frames.forEach(frame => frame.classList.remove('active'));

        // Add active class to clicked button and corresponding frame
        button.classList.add('active');
        document.getElementById(frameId).classList.add('active');
    });
});
