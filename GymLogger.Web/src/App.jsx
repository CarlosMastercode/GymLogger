import React from 'react'

function App() {

    const apiBaseUrl = import.meta.env.VITE_API_BASE_URL || 'https://localhost:7299'
    const [showVerification, setShowVerification] = React.useState(false)
    const [registrationDetails, setRegistrationDetails] = React.useState(null)
    const [showRegistration, setShowRegistration] = React.useState(false)
    const [contactMethod, setContactMethod] = React.useState('email')
    const [registrationMessage, setRegistrationMessage] = React.useState('')
    const [showLogin, setShowLogin] = React.useState(false)
    const [showLoginVerification, setShowLoginVerification] = React.useState(false)
    const [loginEmail, setLoginEmail] = React.useState('')
    const [loginMessage, setLoginMessage] = React.useState('')
    const [showDashboard, setShowDashboard] = React.useState(false)
    const [showWorkout, setShowWorkout] = React.useState(false)
    const [showSetLogger, setShowSetLogger] = React.useState(false)
    const [exercises, setExercises] = React.useState([])
    const [selectedExercise, setSelectedExercise] = React.useState(null)
    const [weight, setWeight] = React.useState('')
    const [reps, setReps] = React.useState('')
    const [completedSets, setCompletedSets] = React.useState([])
    const [workoutSessionId, setWorkoutSessionId] = React.useState(null)
    const [workoutMessage, setWorkoutMessage] = React.useState('')
    const [showHistory, setShowHistory] = React.useState(false)
    const [sessionHistory, setSessionHistory] = React.useState([])
    const [isInitializing, setIsInitializing] = React.useState(true)
    const wheelRef = React.useRef(null)

    function apiUrl(path) {
        return `${apiBaseUrl}${path}`
    }

    function getAuthHeaders() {
        const token = localStorage.getItem('sessionToken')

        return token
            ? { Authorization: `Bearer ${token}` }
            : {}
    }

    React.useEffect(() => {
        async function restoreSession() {
            const token = localStorage.getItem('sessionToken')

            if (!token) {
                setIsInitializing(false)
                return
            }

            try {
                const response = await fetch(apiUrl('/api/auth/me'), {
                    headers: getAuthHeaders(),
                })

                if (!response.ok) {
                    localStorage.removeItem('sessionToken')
                    localStorage.removeItem('userId')
                    return
                }

                const result = await response.json()
                localStorage.setItem('userId', result.userId)
                setShowDashboard(true)
            } catch {
                setWorkoutMessage('Unable to restore your session.')
            } finally {
                setIsInitializing(false)
            }
        }

        restoreSession()
    }, [])

    React.useEffect(() => {
        if (!selectedExercise || !wheelRef.current) return

        const selectedElement = wheelRef.current.querySelector('.selected')

        selectedElement?.scrollIntoView({
            behavior: 'smooth',
            block: 'center',
        })
    }, [selectedExercise])

    React.useEffect(() => {
        if (!showSetLogger) return

        async function loadExercises() {
            try {
                const response = await fetch(apiUrl('/api/exercises'))

                if (!response.ok) {
                    throw new Error('Failed to load exercises.')
                }

                const data = await response.json()

                setExercises(
                    data.sort((a, b) => a.name.localeCompare(b.name))
                )
            } catch (error) {
                console.error('Error loading exercises:', error)
            }
        }

        loadExercises()
    }, [showSetLogger])


    async function handleCompleteSet() {
        const parsedWeight = Number(weight)
        const parsedReps = Number(reps)

        if (
            !selectedExercise ||
            weight === '' ||
            reps === '' ||
            !Number.isFinite(parsedWeight) ||
            !Number.isFinite(parsedReps) ||
            parsedWeight < 0 ||
            parsedReps < 1
        ) {
            return
        }

        if (!workoutSessionId) {
            setWorkoutMessage('Start a workout session before logging a set.')
            return
        }

        try {
            const response = await fetch(
                apiUrl(`/api/workouts/sessions/${workoutSessionId}/sets`),
                {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        ...getAuthHeaders(),
                    },
                    body: JSON.stringify({
                        exerciseId: selectedExercise.id,
                        weight: parsedWeight,
                        reps: parsedReps,
                    }),
                }
            )

            const result = await response.json()

            if (!response.ok) {
                setWorkoutMessage(result.error || 'Unable to log this set.')
                return
            }

            setCompletedSets((previousSets) => [
                ...previousSets,
                {
                    exerciseId: selectedExercise.id,
                    exerciseName: selectedExercise.name,
                    setNumber: result.setNumber,
                    weight: parsedWeight,
                    reps: parsedReps,
                },
            ])
            setWorkoutMessage('')
        } catch {
            setWorkoutMessage('Unable to connect to Gym Logger.')
            return
        }

        setWeight('')
        setReps('')
    }

    async function startWorkoutSession() {
        try {
            const response = await fetch(apiUrl('/api/workouts/sessions'), {
                method: 'POST',
                headers: getAuthHeaders(),
            })

            const result = await response.json()

            if (!response.ok) {
                setWorkoutMessage(result.error || 'Unable to start a workout.')
                return
            }

            setWorkoutSessionId(result.id)
            setCompletedSets([])
            setSelectedExercise(null)
            setWorkoutMessage('')
            setShowDashboard(false)
            setShowSetLogger(true)
        } catch {
            setWorkoutMessage('Unable to connect to Gym Logger.')
        }
    }

    async function loadSessionHistory() {
        try {
            const response = await fetch(apiUrl('/api/workouts/sessions'), {
                headers: getAuthHeaders(),
            })
            const result = await response.json()

            if (!response.ok) {
                setWorkoutMessage(result.error || 'Unable to load sessions.')
                return
            }

            setSessionHistory(result)
            setShowHistory(true)
        } catch {
            setWorkoutMessage('Unable to connect to Gym Logger.')
        }
    }


    async function handleRegistration(event) {
        event.preventDefault()
        setRegistrationMessage('Creating your account...')

        const formData = new FormData(event.currentTarget)

        const request = {
            firstName: formData.get('firstName').trim(),
            lastName: formData.get('lastName').trim(),
            email: contactMethod === 'email'
                ? formData.get('contact').trim()
                : null,
            phoneNumber: contactMethod === 'phone'
                ? formData.get('contact').trim()
                : null,
        }

        try {
            const response = await fetch(apiUrl('/api/users/register'), {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(request),
            })

            const result = await response.json()

            if (!response.ok) {
                setRegistrationMessage(
                    result.error || 'Unable to create your account.'
                )
                return
            }

            setRegistrationDetails({
                email: request.email,
                phoneNumber: request.phoneNumber,
                userId: result.id,
            })

            setRegistrationMessage('')
            setShowVerification(true)

        } catch {
            setRegistrationMessage(
                'Unable to connect to Gym Logger. Please try again.'
            )
        }
    }

    async function handleVerification(event) {
        event.preventDefault()

        const formData = new FormData(event.currentTarget)
        const code = formData.get('verificationCode').trim()

        setRegistrationMessage('Verifying your account...')

        try {
            const response = await fetch(
                apiUrl('/api/auth/verify-registration'),
                {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({
                        email: registrationDetails.email,
                        phoneNumber: registrationDetails.phoneNumber,
                        code,
                        stayLoggedIn: false,
                    }),
                }
            )

            const result = await response.json()

            if (!response.ok) {
                setRegistrationMessage(
                    result.error || 'Unable to verify your account.'
                )
                return
            }

            localStorage.setItem('sessionToken', result.sessionToken)
            localStorage.setItem('userId', result.userId)

            setRegistrationMessage('Account verified successfully! You are now signed in.')
            setShowVerification(false)
            setShowDashboard(true)
        } catch {
            setRegistrationMessage(
                'Unable to connect to Gym Logger. Please try again.'
            )
        }
    }

    async function handleLoginRequest(event) {
        event.preventDefault()

        const formData = new FormData(event.currentTarget)
        const email = formData.get('loginEmail').trim()

        setLoginEmail(email)
        setLoginMessage('Requesting login code...')

        try {
            const response = await fetch(
                apiUrl('/api/auth/request-code'),
                {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({
                        email,
                        phoneNumber: null,
                    }),
                }
            )

            const result = await response.json()

            if (!response.ok) {
                setLoginMessage(
                    result.error || 'Unable to request a login code.'
                )
                return
            }

            setLoginMessage(
                result.developmentCode
                    ? `Development login code: ${result.developmentCode}`
                    : result.message || 'Check your email for your login code.'
            )

            setShowLogin(false)
            setShowLoginVerification(true)
        } catch {
            setLoginMessage(
                'Unable to connect to Gym Logger. Please try again.'
            )
        }
    }

    async function handleLoginVerification(event) {
        event.preventDefault()

        const formData = new FormData(event.currentTarget)
        const code = formData.get('loginCode').trim()
        const stayLoggedIn = formData.get('stayLoggedIn') === 'on'

        setLoginMessage('Verifying login code...')

        try {
            const response = await fetch(
                apiUrl('/api/auth/verify-login'),
                {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({
                        email: loginEmail,
                        phoneNumber: null,
                        code,
                        stayLoggedIn,
                    }),
                }
            )

            const result = await response.json()

            if (!response.ok) {
                setLoginMessage(
                    result.error || 'Unable to sign in.'
                )
                return
            }

            localStorage.setItem('sessionToken', result.sessionToken)
            localStorage.setItem('userId', result.userId)

            setLoginMessage('')
            setShowLoginVerification(false)
            setShowDashboard(true)
        } catch {
            setLoginMessage(
                'Unable to connect to Gym Logger. Please try again.'
            )
        }
    }

    if (isInitializing) {
        return null
    }

    if (showHistory) {
        return (
            <main className="app">
                <section className="hero">
                    <p className="hero-eyebrow">YOUR FITNESS. YOUR DATA.</p>
                    <h1>Your <span>sessions.</span></h1>
                    {sessionHistory.length === 0 ? (
                        <p className="hero-description">
                            No workout sessions have been recorded yet.
                        </p>
                    ) : (
                        <div className="completed-sets">
                            {sessionHistory.map((session) => (
                                <div className="completed-exercise" key={session.id}>
                                    <h2>{new Date(session.startedAt).toLocaleString()}</h2>
                                    <p>{session.status}</p>
                                    {session.sets.map((set) => (
                                        <p key={set.id}>
                                            {set.exerciseName}: {set.weight} lb × {set.reps}
                                        </p>
                                    ))}
                                </div>
                            ))}
                        </div>
                    )}
                    <button
                        className="button button-primary"
                        type="button"
                        onClick={() => setShowHistory(false)}
                    >
                        Back to Dashboard
                    </button>
                </section>
            </main>
        )
    }

    if (showSetLogger) {
        return (
            <main className="app">
                <header className="app-header">
                    <a className="app-logo" href="/">
                        GYM<span>LOGGER</span>
                    </a>
                </header>

                <section className="hero">
                    <p className="hero-eyebrow">YOUR FITNESS. YOUR DATA.</p>

                    <h1>
                        Choose Your <span>Exercise.</span>
                    </h1>

                    <p className="hero-description">
                        What exercise are you working on?
                    </p>

                    <div className="dashboard-options">
                        <div className="exercise-wheel" ref={wheelRef}>
                            {exercises.map((exercise) => (
                                <button
                                    key={exercise.id}
                                    className={`exercise-wheel-item ${selectedExercise?.id === exercise.id ? 'selected' : ''
                                        }`}
                                    type="button"
                                    onClick={() => {
                                        if (selectedExercise?.id === exercise.id) {
                                            setShowSetLogger(false)
                                            setShowWorkout(true)
                                        } else {
                                            setSelectedExercise(exercise)
                                        }
                                    }}
                                >
                                    {exercise.name}
                                </button>
                            ))}
                        </div>

                        <button
                            className="button button-primary"
                            type="button"
                            onClick={() => {
                                setShowSetLogger(false)
                                setShowDashboard(true)
                            }}
                        >
                            Back to Dashboard
                        </button>
                    </div>
                </section>

                <footer className="app-footer">
                    Gym Logger <span>·</span> Built for progress.
                </footer>
            </main>
        )
    }

    if (showWorkout) {
        return (
            <main className="app">
                <header className="app-header">
                    <a className="app-logo" href="/">
                        GYM<span>LOGGER</span>
                    </a>
                </header>

                <section className="hero">
                    <p className="hero-eyebrow">YOUR FITNESS. YOUR DATA.</p>

                    <h1>
                        Log Your <span>{selectedExercise?.name ?? 'Sets'}</span>
                    </h1>

                    <p className="hero-description">
                        Enter your stats!
                    </p>

                    <div className="set-entry-form">
                        <label>
                            Weight Lifted
                            <input
                                type="number"
                                min="0"
                                step="0.5"
                                value={weight}
                                onChange={(event) => setWeight(event.target.value)}
                                placeholder="Enter weight"
                            />
                        </label>

                        <label>
                            Reps Completed
                            <input
                                type="number"
                                min="1"
                                step="1"
                                value={reps}
                                onChange={(event) => setReps(event.target.value)}
                                placeholder="Enter reps"
                            />
                        </label>
                    </div>

                    <button
                        className="button button-primary"
                        type="button"
                        onClick={handleCompleteSet}
                    >
                        Log Set
                    </button>

                    {workoutMessage && (
                        <p role="status" aria-live="polite">
                            {workoutMessage}
                        </p>
                    )}

                    {completedSets.length > 0 && (
                        <div className="completed-sets">
                            <h2>Workout Report</h2>

                            {[...new Set(completedSets.map((set) => set.exerciseId))].map(
                                (exerciseId) => {
                                    const exerciseSets = completedSets.filter(
                                        (set) => set.exerciseId === exerciseId
                                    )

                                    return (
                                        <div className="completed-exercise" key={exerciseId}>
                                            <h3 className="completed-sets-exercise">
                                                {exerciseSets[0].exerciseName}
                                            </h3>

                                            <table>
                                                <thead>
                                                    <tr>
                                                        <th>Set</th>
                                                        <th>Weight (lb)</th>
                                                        <th>Reps</th>
                                                    </tr>
                                                </thead>

                                                <tbody>
                                                    {exerciseSets.map((set) => (
                                                        <tr key={`${exerciseId}-${set.setNumber}`}>
                                                            <td>{set.setNumber}</td>
                                                            <td>{set.weight}</td>
                                                            <td>{set.reps}</td>
                                                        </tr>
                                                    ))}
                                                </tbody>
                                            </table>
                                        </div>
                                    )
                                }
                            )}
                        </div>
                    )}


                    <div className="dashboard-options">
                        <button
                            className="button button-primary"
                            type="button"
                            onClick={() => {
                                setShowWorkout(false)
                                setShowDashboard(false)
                                setShowSetLogger(true)
                            }}
                        >
                            Move to next workout
                        </button>

                        <button
                            className="button button-primary"
                            type="button"
                            onClick={() => {
                                setShowWorkout(false)
                                setShowDashboard(true)
                            }}
                        >
                            Back to Dashboard
                        </button>
                    </div>
                </section>

                <footer className="app-footer">
                    Gym Logger <span>·</span> Built for progress.
                </footer>
            </main>
        )
    }

    if (showDashboard) {
        return (
            <main className="app">
                <header className="app-header">
                    <a className="app-logo" href="/">
                        GYM<span>LOGGER</span>
                    </a>
                </header>

                <section className="hero">
                    <p className="hero-eyebrow">YOUR FITNESS. YOUR DATA.</p>

                    <h1>
                        Welcome to <span>Gym Logger.</span>
                    </h1>

                    <p className="hero-description">
                        What would you like to do today?
                    </p>

                    <div className="dashboard-options">
                        <button
                            className="button button-primary"
                            type="button"
                            onClick={startWorkoutSession}
                        >
                            Start Session
                        </button>

                        <button
                            className="button button-primary"
                            type="button"
                            onClick={loadSessionHistory}
                        >
                            View Prior Sessions
                        </button>

                        <button
                            className="button button-primary"
                            type="button"
                            onClick={loadSessionHistory}
                        >
                            See My Progress
                        </button>
                    </div>
                </section>

                <footer className="app-footer">
                    Gym Logger <span>·</span> Built for progress.
                </footer>
            </main>
        )
    }


    if (showLogin) {
        return (
            <main className="app">
                <section className="hero">
                    <p className="hero-eyebrow">WELCOME BACK</p>

                    <h1>
                        Log in to <span>Gym Logger.</span>
                    </h1>

                    <p className="hero-description">
                        Enter your registered email address to receive a login code.
                    </p>

                    <form
                        className="registration-form"
                        onSubmit={handleLoginRequest}
                    >
                        <label htmlFor="loginEmail">Email address</label>

                        <input
                            id="loginEmail"
                            name="loginEmail"
                            type="email"
                            autoComplete="email"
                            placeholder="you@example.com"
                            defaultValue={loginEmail}
                            required
                        />

                        <button
                            className="button button-primary"
                            type="submit"
                        >
                            Request Login Code
                        </button>

                        {loginMessage && (
                            <p role="status" aria-live="polite">
                                {loginMessage}
                            </p>
                        )}

                        <button
                            className="button button-primary"
                            type="button"
                            onClick={() => {
                                setShowLogin(false)
                                setLoginMessage('')
                            }}
                        >
                            Back
                        </button>
                    </form>
                </section>
            </main>
        )
    }



    if (showLoginVerification) {
        return (
            <main className="app">
                <section className="hero">
                    <p className="hero-eyebrow">WELCOME BACK</p>

                    <h1>
                        Verify your <span>login.</span>
                    </h1>

                    <p className="hero-description">
                        Enter the six-digit login code for {loginEmail}.
                    </p>

                    <form
                        className="registration-form"
                        onSubmit={handleLoginVerification}
                    >
                        <label htmlFor="loginCode">Login code</label>

                        <input
                            id="loginCode"
                            name="loginCode"
                            type="text"
                            inputMode="numeric"
                            pattern="[0-9]{6}"
                            maxLength={6}
                            placeholder="123456"
                            autoComplete="one-time-code"
                            required
                        />

                        <label>
                            <input
                                name="stayLoggedIn"
                                type="checkbox"
                                defaultChecked
                            />
                            Stay logged in for 30 days
                        </label>

                        <button
                            className="button button-primary"
                            type="submit"
                        >
                            Log In
                        </button>

                        {loginMessage && (
                            <p role="status" aria-live="polite">
                                {loginMessage}
                            </p>
                        )}

                        <button
                            className="button button-primary"
                            type="button"
                            onClick={() => {
                                setShowLoginVerification(false)
                                setShowLogin(true)
                                setLoginMessage('')
                            }}
                        >
                            Back to Login
                        </button>
                    </form>
                </section>
            </main>
        )
    }


    if (showVerification) {
        return (
            <main className="app">
                <section className="hero">
                    <p className="hero-eyebrow">ONE LAST STEP</p>

                    <h1>
                        Verify your <span>account.</span>
                    </h1>

                    <p className="hero-description">
                        Enter the six-digit verification code to activate your Gym Logger account.
                    </p>

                    <form className="registration-form" onSubmit={handleVerification}>
                        <label htmlFor="verificationCode">
                            Verification code
                        </label>

                        <input
                            id="verificationCode"
                            name="verificationCode"
                            type="text"
                            inputMode="numeric"
                            pattern="[0-9]{6}"
                            maxLength={6}
                            placeholder="123456"
                            autoComplete="one-time-code"
                            required
                        />

                        <button
                            className="button button-primary"
                            type="submit"
                        >
                            Verify Account
                        </button>

                        <button
                            className="button button-primary"
                            type="button"
                            onClick={() => {
                                setShowVerification(false)
                                setShowRegistration(true)
                            }}
                        >
                            Back to Registration
                        </button>

                        {registrationMessage && (
                            <p role="status" aria-live="polite">
                                {registrationMessage}
                            </p>
                        )}

                    </form>
                </section>
            </main>
        )
    }

    if (showRegistration) {
        return (
            <main className="app">
                <section className="hero">
                    <p className="hero-eyebrow">YOUR FITNESS. YOUR DATA.</p>

                    <h1>
                        Create your <span>account.</span>
                    </h1>

                    <p className="hero-description">
                        Start tracking your workouts and building better habits.
                    </p>

                    <form className="registration-form" onSubmit={handleRegistration}>
                        <label htmlFor="firstName">First name</label>
                        <input
                            id="firstName"
                            name="firstName"
                            type="text"
                            autoComplete="given-name"
                            required
                        />

                        <label htmlFor="lastName">Last name</label>
                        <input
                            id="lastName"
                            name="lastName"
                            type="text"
                            autoComplete="family-name"
                            required
                        />

                        <label htmlFor="contactMethod">Contact method</label>
                        <select
                            id="contactMethod"
                            name="contactMethod"
                            value={contactMethod}
                            onChange={(event) => setContactMethod(event.target.value)}
                        >
                            <option value="email">Email address</option>
                            <option value="phone">Phone number</option>
                        </select>

                        <label htmlFor="contact">
                            {contactMethod === 'email' ? 'Email address' : 'Phone number'}
                        </label>

                        <input
                            id="contact"
                            name="contact"
                            type={contactMethod === 'email' ? 'email' : 'tel'}
                            autoComplete={contactMethod === 'email' ? 'email' : 'tel'}
                            placeholder={
                                contactMethod === 'email'
                                    ? 'you@example.com'
                                    : '(555) 123-4567'
                            }
                            maxLength={contactMethod === 'email' ? 254 : 20}
                            required
                        />

                        <button className="button button-primary" type="submit">
                            Create Account
                        </button>

                        {registrationMessage && (
                            <p role="status" aria-live="polite">
                                {registrationMessage}
                            </p>
                        )}

                        <button
                            className="button button-primary"
                            type="button"
                            onClick={() => setShowRegistration(false)}
                        >
                            Back
                        </button>
                    </form>
                </section>
            </main>
        )
    }

    return (
        <main className="app">
            <header className="app-header">
                <a className="app-logo" href="/">
                    GYM<span>LOGGER</span>
                </a>
                <div className="dashboard-options">
                    <button
                        className="button button-primary"
                        type="button"
                        onClick={() => {
                            setLoginMessage('')
                            setShowLogin(true)
                        }}
                    >
                        Log In
                    </button>

                    <button
                        className="button button-primary"
                        type="button"
                        onClick={() => setShowRegistration(true)}
                    >
                        Register
                    </button>
                </div>
            </header>

            <section className="hero">
                <p className="hero-eyebrow">YOUR FITNESS. YOUR DATA.</p>

                <h1>
                    Every rep.
                    <br />
                    Every <span>step forward.</span>
                </h1>

                <p className="hero-description">
                    Track your workouts, record every set, and see your progress over time.
                </p>

                <button
                    className="button button-primary"
                    type="button"
                    onClick={() => setShowRegistration(true)}
                >
                    Get Started
                </button>
            </section>

            <footer className="app-footer">
                Gym Logger <span>·</span> Built for progress.
            </footer>
        </main>
    )
}

export default App
